#!/usr/bin/env python3
"""Tests for format-pods.py"""
import json
import os
import re
import sys
import tempfile
import pytest
from datetime import datetime, timezone, timedelta

# Add lib directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

# Import the module (remove .py extension for import)
import importlib.util

spec = importlib.util.spec_from_file_location(
    "format_pods",
    os.path.join(os.path.dirname(__file__), "..", "lib", "format-pods.py"),
)
format_pods = importlib.util.module_from_spec(spec)
spec.loader.exec_module(format_pods)


# ============================================================================
# Test fixtures
# ============================================================================


@pytest.fixture
def output_dir():
    """Create temporary output directory"""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield tmpdir


@pytest.fixture
def running_pod():
    """Sample running pod data"""
    return {
        "items": [
            {
                "metadata": {
                    "name": "nginx-pod",
                    "creationTimestamp": (
                        datetime.now(timezone.utc) - timedelta(days=1)
                    ).isoformat(),
                },
                "spec": {"containers": [{"name": "nginx", "image": "nginx:latest"}]},
                "status": {
                    "phase": "Running",
                    "containerStatuses": [
                        {
                            "name": "nginx",
                            "ready": True,
                            "restartCount": 0,
                            "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}},
                        }
                    ],
                },
            }
        ]
    }


@pytest.fixture
def pending_pod():
    """Sample pending pod data"""
    return {
        "items": [
            {
                "metadata": {
                    "name": "pending-pod",
                    "creationTimestamp": datetime.now(timezone.utc).isoformat(),
                },
                "spec": {"containers": [{"name": "app", "image": "app:v1"}]},
                "status": {
                    "phase": "Pending",
                    "containerStatuses": [
                        {
                            "name": "app",
                            "ready": False,
                            "restartCount": 0,
                            "state": {"waiting": {"reason": "ContainerCreating"}},
                        }
                    ],
                },
            }
        ]
    }


@pytest.fixture
def crashloop_pod():
    """Sample pod in CrashLoopBackOff"""
    return {
        "items": [
            {
                "metadata": {
                    "name": "crash-pod",
                    "creationTimestamp": datetime.now(timezone.utc).isoformat(),
                },
                "spec": {"containers": [{"name": "app", "image": "app:v1"}]},
                "status": {
                    "phase": "Running",
                    "containerStatuses": [
                        {
                            "name": "app",
                            "ready": False,
                            "restartCount": 5,
                            "state": {"waiting": {"reason": "CrashLoopBackOff"}},
                        }
                    ],
                },
            }
        ]
    }


@pytest.fixture
def completed_pod():
    """Sample completed job pod"""
    return {
        "items": [
            {
                "metadata": {
                    "name": "job-pod",
                    "creationTimestamp": datetime.now(timezone.utc).isoformat(),
                },
                "spec": {"containers": [{"name": "job", "image": "job:v1"}]},
                "status": {
                    "phase": "Succeeded",
                    "containerStatuses": [
                        {
                            "name": "job",
                            "ready": False,
                            "restartCount": 0,
                            "state": {
                                "terminated": {"reason": "Completed", "exitCode": 0}
                            },
                        }
                    ],
                },
            }
        ]
    }


@pytest.fixture
def terminating_pod():
    """Sample terminating pod"""
    return {
        "items": [
            {
                "metadata": {
                    "name": "terminating-pod",
                    "creationTimestamp": datetime.now(timezone.utc).isoformat(),
                    "deletionTimestamp": datetime.now(timezone.utc).isoformat(),
                },
                "spec": {"containers": [{"name": "app", "image": "app:v1"}]},
                "status": {
                    "phase": "Running",
                    "containerStatuses": [
                        {
                            "name": "app",
                            "ready": True,
                            "restartCount": 0,
                            "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}},
                        }
                    ],
                },
            }
        ]
    }


@pytest.fixture
def pod_with_init_container():
    """Sample pod with init container"""
    return {
        "items": [
            {
                "metadata": {
                    "name": "init-pod",
                    "creationTimestamp": datetime.now(timezone.utc).isoformat(),
                },
                "spec": {
                    "initContainers": [{"name": "init", "image": "busybox"}],
                    "containers": [{"name": "app", "image": "app:v1"}],
                },
                "status": {
                    "phase": "Running",
                    "initContainerStatuses": [
                        {
                            "name": "init",
                            "ready": False,
                            "restartCount": 0,
                            "state": {
                                "terminated": {"reason": "Completed", "exitCode": 0}
                            },
                        }
                    ],
                    "containerStatuses": [
                        {
                            "name": "app",
                            "ready": True,
                            "restartCount": 0,
                            "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}},
                        }
                    ],
                },
            }
        ]
    }


@pytest.fixture
def multi_container_pod():
    """Sample pod with multiple containers"""
    return {
        "items": [
            {
                "metadata": {
                    "name": "multi-pod",
                    "creationTimestamp": datetime.now(timezone.utc).isoformat(),
                },
                "spec": {
                    "containers": [
                        {"name": "app", "image": "app:v1"},
                        {"name": "sidecar", "image": "sidecar:v1"},
                    ]
                },
                "status": {
                    "phase": "Running",
                    "containerStatuses": [
                        {
                            "name": "app",
                            "ready": True,
                            "restartCount": 0,
                            "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}},
                        },
                        {
                            "name": "sidecar",
                            "ready": True,
                            "restartCount": 2,
                            "state": {"running": {"startedAt": "2024-01-01T00:00:00Z"}},
                        },
                    ],
                },
            }
        ]
    }


# ============================================================================
# format_duration() tests
# ============================================================================


class TestFormatDuration:
    def test_seconds(self):
        assert format_pods.format_duration(30) == "30s"
        assert format_pods.format_duration(59) == "59s"

    def test_minutes(self):
        assert format_pods.format_duration(60) == "1m0s"
        assert format_pods.format_duration(90) == "1m30s"
        assert format_pods.format_duration(3599) == "59m59s"

    def test_hours(self):
        assert format_pods.format_duration(3600) == "1h0m"
        assert format_pods.format_duration(7200) == "2h0m"
        assert format_pods.format_duration(3660) == "1h1m"

    def test_days(self):
        assert format_pods.format_duration(86400) == "1d0h"
        assert format_pods.format_duration(90000) == "1d1h"
        assert format_pods.format_duration(172800) == "2d0h"


# ============================================================================
# get_pod_status() tests
# ============================================================================


class TestGetPodStatus:
    def test_running_pod(self, running_pod):
        pod = running_pod["items"][0]
        assert format_pods.get_pod_status(pod) == "Running"

    def test_pending_pod(self, pending_pod):
        pod = pending_pod["items"][0]
        assert format_pods.get_pod_status(pod) == "ContainerCreating"

    def test_crashloop_pod(self, crashloop_pod):
        pod = crashloop_pod["items"][0]
        assert format_pods.get_pod_status(pod) == "CrashLoopBackOff"

    def test_completed_pod(self, completed_pod):
        pod = completed_pod["items"][0]
        assert format_pods.get_pod_status(pod) == "Completed"

    def test_terminating_pod(self, terminating_pod):
        pod = terminating_pod["items"][0]
        assert format_pods.get_pod_status(pod) == "Terminating"


# ============================================================================
# get_container_state() tests
# ============================================================================


class TestGetContainerState:
    def test_running_state(self):
        state = {"running": {"startedAt": "2024-01-01T00:00:00Z"}}
        is_ready, desc = format_pods.get_container_state(state)
        assert is_ready is True
        assert desc == "Running"

    def test_waiting_state(self):
        state = {"waiting": {"reason": "ContainerCreating"}}
        is_ready, desc = format_pods.get_container_state(state)
        assert is_ready is False
        assert desc == "ContainerCreating"

    def test_terminated_completed(self):
        state = {"terminated": {"reason": "Completed", "exitCode": 0}}
        is_ready, desc = format_pods.get_container_state(state)
        assert is_ready is True
        assert desc == "Completed"

    def test_terminated_error(self):
        state = {"terminated": {"reason": "Error", "exitCode": 1}}
        is_ready, desc = format_pods.get_container_state(state)
        assert is_ready is False
        assert desc == "Error"

    def test_unknown_state(self):
        state = {}
        is_ready, desc = format_pods.get_container_state(state)
        assert is_ready is False
        assert desc == "Unknown"


# ============================================================================
# get_status_color() tests
# ============================================================================


class TestGetStatusColor:
    def test_error_status(self):
        assert format_pods.get_status_color("Error") == "RED"
        assert format_pods.get_status_color("CrashLoopBackOff") == "RED"
        assert format_pods.get_status_color("OOMKilled") == "RED"

    def test_completed_status(self):
        assert format_pods.get_status_color("Completed") == "GRAY"
        assert format_pods.get_status_color("Terminated") == "GRAY"

    def test_normal_status(self):
        assert format_pods.get_status_color("Running") is None
        assert format_pods.get_status_color("Pending") is None


# ============================================================================
# build_pods_table() tests
# ============================================================================


class TestBuildPodsTable:
    def test_running_pod_table(self, running_pod):
        table = format_pods.build_pods_table(running_pod)
        assert len(table) == 1
        # Strip ANSI codes for comparison
        row = [re.sub(r"\033\[[0-9;]*m", "", str(cell)) for cell in table[0]]
        assert row[0] == "nginx-pod"
        assert row[1] == "1/1"
        assert row[2] == "Running"
        assert row[3] == "0"

    def test_multi_container_pod_table(self, multi_container_pod):
        table = format_pods.build_pods_table(multi_container_pod)
        assert len(table) == 1
        row = [re.sub(r"\033\[[0-9;]*m", "", str(cell)) for cell in table[0]]
        assert row[0] == "multi-pod"
        assert row[1] == "2/2"
        assert row[3] == "2"  # total restarts

    def test_empty_items(self):
        table = format_pods.build_pods_table({"items": []})
        assert len(table) == 0


# ============================================================================
# build_containers_table() tests
# ============================================================================


class TestBuildContainersTable:
    def test_single_container(self, running_pod):
        table = format_pods.build_containers_table(running_pod)
        assert len(table) == 1
        row = [re.sub(r"\033\[[0-9;]*m", "", str(cell)) for cell in table[0]]
        assert row[0] == "nginx-pod"
        assert row[1] == "nginx"
        assert row[2] == "true"
        assert row[3] == "Running"
        assert row[4] == "nginx:latest"

    def test_multi_container(self, multi_container_pod):
        table = format_pods.build_containers_table(multi_container_pod)
        assert len(table) == 2
        names = [re.sub(r"\033\[[0-9;]*m", "", str(row[1])) for row in table]
        assert "app" in names
        assert "sidecar" in names

    def test_init_container(self, pod_with_init_container):
        table = format_pods.build_containers_table(pod_with_init_container)
        assert len(table) == 2
        names = [re.sub(r"\033\[[0-9;]*m", "", str(row[1])) for row in table]
        assert "init" in names
        assert "app" in names


# ============================================================================
# format_table() tests
# ============================================================================


class TestFormatTable:
    def test_basic_table(self):
        data = [["pod-1", "1/1", "Running"]]
        headers = ["NAME", "READY", "STATUS"]
        result = format_pods.format_table(data, headers)
        assert "NAME" in result
        assert "pod-1" in result
        assert "Running" in result

    def test_empty_data(self):
        headers = ["NAME", "READY"]
        result = format_pods.format_table([], headers)
        assert "NAME" in result
        assert "READY" in result

    def test_handles_ansi_codes(self):
        colored_cell = "\033[92mRunning\033[0m"
        data = [["pod-1", colored_cell]]
        headers = ["NAME", "STATUS"]
        result = format_pods.format_table(data, headers)
        # Should handle ANSI without breaking alignment
        assert "pod-1" in result


# ============================================================================
# Integration tests
# ============================================================================


class TestIntegration:
    def test_full_pipeline(self, output_dir, running_pod):
        """Test complete processing pipeline"""
        # Write input data
        input_file = os.path.join(output_dir, "input.json")
        with open(input_file, "w") as f:
            json.dump(running_pod, f)

        # Process data
        data = format_pods.load_data(input_file)
        pod_data = format_pods.build_pods_table(data)
        container_data = format_pods.build_containers_table(data)

        # Write outputs
        format_pods.write_table(
            pod_data,
            ["NAME", "READY", "STATUS", "RESTARTS", "AGE"],
            os.path.join(output_dir, "pods"),
        )
        format_pods.write_table(
            container_data,
            ["POD", "NAME", "READY", "STATUS", "IMAGE"],
            os.path.join(output_dir, "containers"),
        )

        # Verify outputs exist and have content
        pods_file = os.path.join(output_dir, "pods")
        containers_file = os.path.join(output_dir, "containers")

        assert os.path.exists(pods_file)
        assert os.path.exists(containers_file)

        with open(pods_file) as f:
            pods_content = f.read()
            assert "nginx-pod" in pods_content
            assert "Running" in pods_content

        with open(containers_file) as f:
            containers_content = f.read()
            assert "nginx" in containers_content

    def test_multiple_pods(self):
        """Test with multiple pods of different statuses"""
        data = {
            "items": [
                {
                    "metadata": {
                        "name": "running-pod",
                        "creationTimestamp": datetime.now(timezone.utc).isoformat(),
                    },
                    "spec": {"containers": [{"name": "app", "image": "app:v1"}]},
                    "status": {
                        "phase": "Running",
                        "containerStatuses": [
                            {
                                "name": "app",
                                "ready": True,
                                "restartCount": 0,
                                "state": {"running": {}},
                            }
                        ],
                    },
                },
                {
                    "metadata": {
                        "name": "pending-pod",
                        "creationTimestamp": datetime.now(timezone.utc).isoformat(),
                    },
                    "spec": {"containers": [{"name": "app", "image": "app:v1"}]},
                    "status": {
                        "phase": "Pending",
                        "containerStatuses": [
                            {
                                "name": "app",
                                "ready": False,
                                "restartCount": 0,
                                "state": {"waiting": {"reason": "ImagePullBackOff"}},
                            }
                        ],
                    },
                },
                {
                    "metadata": {
                        "name": "completed-pod",
                        "creationTimestamp": datetime.now(timezone.utc).isoformat(),
                    },
                    "spec": {"containers": [{"name": "job", "image": "job:v1"}]},
                    "status": {
                        "phase": "Succeeded",
                        "containerStatuses": [
                            {
                                "name": "job",
                                "ready": False,
                                "restartCount": 0,
                                "state": {
                                    "terminated": {"reason": "Completed", "exitCode": 0}
                                },
                            }
                        ],
                    },
                },
            ]
        }

        pod_table = format_pods.build_pods_table(data)
        assert len(pod_table) == 3

        # Check each pod status
        statuses = [re.sub(r"\033\[[0-9;]*m", "", str(row[2])) for row in pod_table]
        assert "Running" in statuses
        assert "ImagePullBackOff" in statuses
        assert "Completed" in statuses


# ============================================================================
# Edge cases
# ============================================================================


class TestEdgeCases:
    def test_missing_metadata(self):
        data = {"items": [{"spec": {"containers": []}, "status": {"phase": "Unknown"}}]}
        table = format_pods.build_pods_table(data)
        assert len(table) == 1
        row = [re.sub(r"\033\[[0-9;]*m", "", str(cell)) for cell in table[0]]
        assert row[0] == "unknown"

    def test_missing_container_statuses(self):
        data = {
            "items": [
                {
                    "metadata": {
                        "name": "no-status-pod",
                        "creationTimestamp": datetime.now(timezone.utc).isoformat(),
                    },
                    "spec": {"containers": [{"name": "app", "image": "app:v1"}]},
                    "status": {"phase": "Pending"},
                }
            ]
        }
        table = format_pods.build_pods_table(data)
        assert len(table) == 1
        row = [re.sub(r"\033\[[0-9;]*m", "", str(cell)) for cell in table[0]]
        assert row[1] == "0/1"

    def test_init_container_waiting(self):
        data = {
            "items": [
                {
                    "metadata": {
                        "name": "init-waiting",
                        "creationTimestamp": datetime.now(timezone.utc).isoformat(),
                    },
                    "spec": {
                        "initContainers": [{"name": "init", "image": "busybox"}],
                        "containers": [{"name": "app", "image": "app:v1"}],
                    },
                    "status": {
                        "phase": "Pending",
                        "initContainerStatuses": [
                            {
                                "name": "init",
                                "ready": False,
                                "restartCount": 0,
                                "state": {"waiting": {"reason": "PodInitializing"}},
                            }
                        ],
                    },
                }
            ]
        }
        pod = data["items"][0]
        status = format_pods.get_pod_status(pod)
        assert "Init:" in status
