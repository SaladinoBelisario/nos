package state

import (
	"fmt"
	"github.com/nebuly-ai/nebulnetes/pkg/resource"
	v1 "k8s.io/api/core/v1"
	"k8s.io/kubernetes/pkg/scheduler/framework"
)

func NewClusterSnapshot(nodes map[string]*framework.NodeInfo) ClusterSnapshot {
	data := snapshotData{nodes: nodes}
	return ClusterSnapshot{data: &data}
}

type snapshotData struct {
	nodes map[string]*framework.NodeInfo
}

func (d snapshotData) clone() *snapshotData {
	res := snapshotData{
		nodes: make(map[string]*framework.NodeInfo),
	}
	for k, v := range d.nodes {
		res.nodes[k] = v.Clone()
	}
	return &res
}

type ClusterSnapshot struct {
	data       *snapshotData
	forkedData *snapshotData
}

func (c *ClusterSnapshot) getData() *snapshotData {
	if c.forkedData != nil {
		return c.forkedData
	}
	return c.data
}

func (c *ClusterSnapshot) Fork() error {
	if c.forkedData != nil {
		return fmt.Errorf("snapshot already forked")
	}
	c.forkedData = c.getData().clone()
	return nil
}

func (c *ClusterSnapshot) Commit() {
	if c.forkedData != nil {
		c.data = c.forkedData
		c.forkedData = nil
	}
}

func (c *ClusterSnapshot) Revert() {
	c.forkedData = nil
}

func (c *ClusterSnapshot) GetLackingResources(pod v1.Pod) framework.Resource {
	podRequest := resource.ComputePodRequest(pod)
	totalAllocatable := framework.Resource{}
	totalRequested := framework.Resource{}
	for _, n := range c.GetNodes() {
		totalAllocatable = resource.Sum(totalAllocatable, *n.Allocatable)
		totalRequested = resource.Sum(totalRequested, *n.Requested)
	}
	available := resource.Subtract(totalAllocatable, totalRequested)

	res := resource.Subtract(available, resource.FromListToFramework(podRequest))
	return resource.Abs(res)
}

func (c *ClusterSnapshot) GetNodes() map[string]*framework.NodeInfo {
	return c.getData().nodes
}

func (c *ClusterSnapshot) GetNode(name string) (*framework.NodeInfo, bool) {
	node, found := c.GetNodes()[name]
	return node, found
}

func (c *ClusterSnapshot) SetNode(nodeInfo *framework.NodeInfo) {
	c.getData().nodes[nodeInfo.Node().Name] = nodeInfo
}

func (c *ClusterSnapshot) AddPod(nodeName string, pod v1.Pod) error {
	node, found := c.getData().nodes[nodeName]
	if !found {
		return fmt.Errorf("could not find node %s in cluster snapshot", nodeName)
	}
	node.AddPod(&pod)
	return nil
}
