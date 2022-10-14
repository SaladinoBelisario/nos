package migagent

import (
	"context"
	"github.com/nebuly-ai/nebulnetes/pkg/api/n8s.nebuly.ai/v1alpha1"
	"github.com/nebuly-ai/nebulnetes/pkg/controllers/migagent/types"
	"github.com/nebuly-ai/nebulnetes/pkg/gpu/mig"
	migtypes "github.com/nebuly-ai/nebulnetes/pkg/gpu/mig/types"
	"github.com/nebuly-ai/nebulnetes/pkg/util/resource"
	v1 "k8s.io/api/core/v1"
	"k8s.io/klog/v2"
	"reflect"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"strings"
	"time"
)

type MigReporter struct {
	client.Client
	migClient       mig.Client
	refreshInterval time.Duration
}

func NewReporter(client client.Client, migClient mig.Client, refreshInterval time.Duration) MigReporter {
	reporter := MigReporter{
		Client:          client,
		migClient:       migClient,
		refreshInterval: refreshInterval,
	}
	return reporter
}

func (r *MigReporter) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := klog.FromContext(ctx).WithName("Reporter")
	logger.Info("reporting MIG resources status")

	var instance v1.Node
	if err := r.Client.Get(ctx, client.ObjectKey{Name: req.Name, Namespace: req.Namespace}, &instance); err != nil {
		return ctrl.Result{}, err
	}

	// Compute new status annotations
	migResources, err := r.migClient.GetMigDeviceResources(ctx)
	if err != nil {
		logger.Error(err, "unable to get MIG device resources")
		return ctrl.Result{}, err
	}
	usedMigs := make([]migtypes.MigDeviceResource, 0)
	freeMigs := make([]migtypes.MigDeviceResource, 0)
	for _, r := range migResources {
		if r.Status == resource.StatusUsed {
			usedMigs = append(usedMigs, r)
		}
		if r.Status == resource.StatusFree {
			freeMigs = append(freeMigs, r)
		}
	}
	logger.V(3).Info("loaded free MIG devices", "freeMIGs", freeMigs)
	logger.V(3).Info("loaded used MIG devices", "usedMIGs", usedMigs)
	newStatusAnnotations := computeStatusAnnotations(usedMigs, freeMigs)

	// Get current status annotations and compare with new ones
	oldStatusAnnotations, _ := types.GetGPUAnnotationsFromNode(instance)
	if reflect.DeepEqual(newStatusAnnotations, oldStatusAnnotations) {
		logger.Info("current status is equal to last reported status, nothing to do")
		return ctrl.Result{RequeueAfter: r.refreshInterval}, nil
	}

	// Update node
	logger.Info("status changed - reporting it by updating node annotations")
	updated := instance.DeepCopy()
	for k := range updated.Annotations {
		if strings.HasPrefix(k, v1alpha1.AnnotationGPUStatusPrefix) {
			delete(updated.Annotations, k)
		}
	}
	for _, a := range newStatusAnnotations {
		updated.Annotations[a.Name] = a.GetValue()
	}
	if err := r.Client.Patch(ctx, updated, client.MergeFrom(&instance)); err != nil {
		logger.Error(err, "unable to update node status annotations", "annotations", updated.Annotations)
		return ctrl.Result{}, err
	}

	logger.Info("updated reported status - node annotations updated successfully")
	return ctrl.Result{RequeueAfter: r.refreshInterval}, nil
}

func (r *MigReporter) SetupWithManager(mgr ctrl.Manager, controllerName string, nodeName string) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(
			&v1.Node{},
			builder.WithPredicates(
				excludeDeletePredicate{},
				matchingNamePredicate{Name: nodeName},
				nodeResourcesChangedPredicate{},
			),
		).
		Named(controllerName).
		Complete(r)
}