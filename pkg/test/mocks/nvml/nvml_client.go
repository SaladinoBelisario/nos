// Code generated by mockery v2.14.1. DO NOT EDIT.

package nvml

import (
	gpu "github.com/nebuly-ai/nebulnetes/pkg/gpu"
	mock "github.com/stretchr/testify/mock"
)

// Client is an autogenerated mock type for the Client type
type Client struct {
	mock.Mock
}

// CreateMigDevices provides a mock function with given fields: migProfileNames, gpuIndex
func (_m *Client) CreateMigDevices(migProfileNames []string, gpuIndex int) gpu.Error {
	ret := _m.Called(migProfileNames, gpuIndex)

	var r0 gpu.Error
	if rf, ok := ret.Get(0).(func([]string, int) gpu.Error); ok {
		r0 = rf(migProfileNames, gpuIndex)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(gpu.Error)
		}
	}

	return r0
}

// DeleteMigDevice provides a mock function with given fields: id
func (_m *Client) DeleteMigDevice(id string) gpu.Error {
	ret := _m.Called(id)

	var r0 gpu.Error
	if rf, ok := ret.Get(0).(func(string) gpu.Error); ok {
		r0 = rf(id)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(gpu.Error)
		}
	}

	return r0
}

// GetGpuIndex provides a mock function with given fields: migDeviceId
func (_m *Client) GetGpuIndex(migDeviceId string) (int, gpu.Error) {
	ret := _m.Called(migDeviceId)

	var r0 int
	if rf, ok := ret.Get(0).(func(string) int); ok {
		r0 = rf(migDeviceId)
	} else {
		r0 = ret.Get(0).(int)
	}

	var r1 gpu.Error
	if rf, ok := ret.Get(1).(func(string) gpu.Error); ok {
		r1 = rf(migDeviceId)
	} else {
		if ret.Get(1) != nil {
			r1 = ret.Get(1).(gpu.Error)
		}
	}

	return r0, r1
}

type mockConstructorTestingTNewClient interface {
	mock.TestingT
	Cleanup(func())
}

// NewClient creates a new instance of Client. It also registers a testing interface on the mock and a cleanup function to assert the mocks expectations.
func NewClient(t mockConstructorTestingTNewClient) *Client {
	mock := &Client{}
	mock.Mock.Test(t)

	t.Cleanup(func() { mock.AssertExpectations(t) })

	return mock
}
