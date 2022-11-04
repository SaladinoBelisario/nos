package core

import (
	"context"
	"github.com/nebuly-ai/nebulnetes/internal/controllers/gpupartitioner/state"
	"github.com/nebuly-ai/nebulnetes/pkg/constant"
	"github.com/nebuly-ai/nebulnetes/pkg/util/pod"
	v1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sort"
)

type Controller struct {
	Scheme       *runtime.Scheme
	clusterState *state.ClusterState
	planner      Planner
	actuator     Actuator
}

func NewController(
	scheme *runtime.Scheme,
	clusterState *state.ClusterState,
	planner Planner,
	actuator Actuator) Controller {
	return Controller{
		Scheme:       scheme,
		clusterState: clusterState,
		planner:      planner,
		actuator:     actuator,
	}
}

//+kubebuilder:rbac:groups=core,resources=pods,verbs=get;list;watch
//+kubebuilder:rbac:groups=core,resources=nodes,verbs=get;list;watch;patch

func (c *Controller) Reconcile(ctx context.Context, _ ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithName("GPUPartitioner")
	logger.V(3).Info("*** start reconcile ***")
	defer logger.V(3).Info("*** end reconcile ***")

	snapshot := c.clusterState.GetSnapshot()

	// Keep only pending pods that could benefit from
	// extra resources created through GPU partitioning
	pendingCandidates := make([]v1.Pod, 0)
	for _, p := range snapshot.GetPendingPods() {
		if pod.ExtraResourcesCouldHelpScheduling(p) {
			pendingCandidates = append(pendingCandidates, p)
		}
	}
	if len(pendingCandidates) == 0 {
		logger.Info("there are no pending pods to help with GPU partitioning")
		return ctrl.Result{}, nil
	}

	// Sort Pods by importance
	sort.Slice(pendingCandidates, func(i, j int) bool {
		return pod.IsMoreImportant(pendingCandidates[i], pendingCandidates[j])
	})

	// Compute desired state
	desiredState, err := c.planner.Plan(ctx, snapshot, pendingCandidates)
	if err != nil {
		logger.Error(err, "unable to plan desired partitioning state")
		return ctrl.Result{}, err
	}

	// Apply partitioning plan
	if err = c.actuator.Apply(ctx, snapshot, desiredState); err != nil {
		logger.Error(err, "unable to apply desired partitioning state")
		return ctrl.Result{}, err
	}

	return ctrl.Result{}, nil
}

func (c *Controller) SetupWithManager(mgr ctrl.Manager, name string) error {
	err := mgr.GetFieldIndexer().IndexField(context.Background(), &v1.Pod{}, constant.PodPhaseKey, func(rawObj client.Object) []string {
		p := rawObj.(*v1.Pod)
		return []string{string(p.Status.Phase)}
	})
	if err != nil {
		return err
	}

	return ctrl.NewControllerManagedBy(mgr).
		For(&v1.Pod{}).
		Named(name).
		Complete(c)
}
