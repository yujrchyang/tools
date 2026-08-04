#!/usr/bin/env python3
import os
import sys
import json
import shutil
import signal
import time
import glob
import subprocess
import argparse
from pathlib import Path
from typing import Any, Dict, List
from abc import ABC, abstractmethod
from urllib.request import urlopen
from urllib.error import URLError, HTTPError


class CommandExecutor:
    """Command execution helper: subprocess calls + HTTP GET for service checks."""

    @staticmethod
    def _get_run_kwargs(capture_output: bool) -> Dict[str, Any]:
        if sys.version_info >= (3, 7):
            text_mode = {"text": True}
        else:
            text_mode = {"universal_newlines": True}
        return {
            "shell": False,
            "stdout": subprocess.PIPE if capture_output else None,
            "stderr": subprocess.PIPE if capture_output else None,
            **text_mode,
        }

    @staticmethod
    def run(command: List[str], capture_output: bool = True) -> str:
        try:
            result = subprocess.run(
                command,
                check=True,
                **CommandExecutor._get_run_kwargs(capture_output)
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            print(f"failed to exec : {command} - {e.stderr}", file=sys.stderr)
            sys.exit(1)

    @staticmethod
    def run_raw(command: List[str]) -> subprocess.CompletedProcess:
        return subprocess.run(
            command,
            check=False,
            **CommandExecutor._get_run_kwargs(True)
        )

    @staticmethod
    def run_background_daemon(command: List[str], logfile: str):
        pid = os.fork()
        if pid > 0:
            return pid
        os.setsid()
        pid = os.fork()
        if pid > 0:
            os._exit(0)
        sys.stdout.flush()
        sys.stderr.flush()
        if logfile == "":
            logfile = "/dev/null"
        with open(logfile, 'ab', buffering=0) as log:
            os.dup2(log.fileno(), sys.stdout.fileno())
            os.dup2(log.fileno(), sys.stderr.fileno())
        with open('/dev/null', 'rb') as f:
            os.dup2(f.fileno(), sys.stdin.fileno())
        os.execvp(command[0], command)
        os._exit(255)

    @staticmethod
    def run_http_get_json(url: str, timeout=5) -> Any:
        try:
            with urlopen(url, timeout=timeout) as response:
                if response.status != 200:
                    return {}
                return json.loads(response.read().decode('utf-8'))
        except (URLError, HTTPError, TimeoutError, ValueError,
               UnicodeDecodeError, AttributeError):
            pass
        return {}


class ConfigFileManager:
    @staticmethod
    def get_json_data(json_path: str) -> Dict:
        try:
            with open(json_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            print(f"error: input json file {json_path} does not exist.")
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"error: invalid json format of {json_path} : {str(e)}")
            sys.exit(1)
        except Exception as e:
            print(f"error: read json file {json_path} failed : {str(e)}")
            sys.exit(1)


class DirectoryManager:
    def __init__(self, cfg_dir: str) -> None:
        VSTART_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
        self.bin_dir = os.path.abspath(os.path.join(VSTART_SCRIPT_DIR, '../build/bin/blobstore'))
        self.lib_dir = os.path.abspath(os.path.join(VSTART_SCRIPT_DIR, './run/lib'))
        self.log_dir = os.path.abspath(os.path.join(VSTART_SCRIPT_DIR, './run/log'))
        self.cfg_dir = os.path.abspath(os.path.join(VSTART_SCRIPT_DIR, cfg_dir))
        self.all_dirs = [self.lib_dir, self.log_dir]

    def setup_directory(self) -> None:
        for dir in self.all_dirs:
            Path(dir).mkdir(parents=True, exist_ok=True)

    def remove_directory(self) -> None:
        for dir in self.all_dirs:
            dir_path = Path(dir)
            if dir_path.exists():
                shutil.rmtree(dir_path)


class ServiceBase(ABC):
    # Binary name (under dir_manager.bin_dir) for services launched the standard
    # way: `<bin_dir>/<BINARY> -f <cfg_file>`. Subclasses with custom launch
    # (consul/kafka) override _setup_service.
    BINARY: str = ""

    def __init__(self, args: argparse.Namespace, dir_manager: DirectoryManager,
                 process_identifier: str, cfg_file: str, start_log_file: str) -> None:
        self.args = args
        self.dir_manager = dir_manager
        self.process_identifier = process_identifier
        self.cfg_file = f"{self.dir_manager.cfg_dir}/{cfg_file}"
        self.start_log_file = f"{self.dir_manager.log_dir}/{start_log_file}"
        self.command: List[str] = []

    def run_service(self) -> None:
        self._setup_service()
        self._start_service()
        self._check_service()

    def stop_service(self) -> None:
        print(f"stopping {self.process_identifier} ...")
        current_pid = os.getpid()
        for pid in glob.glob("/proc/[0-9]*"):
            pid_num = int(pid.split("/")[-1])
            if pid_num == current_pid:
                continue
            try:
                if self.process_identifier in open(f"{pid}/cmdline").read().replace("\0", " "):
                    os.kill(pid_num, signal.SIGKILL)
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                pass
        time.sleep(1)

    # -- shared helpers ----------------------------------------------------

    def _setup_service(self) -> None:
        """Default setup: launch bin_dir/BINARY with -f cfg_file."""
        print(f"starting {self.BINARY} ...")
        self.command = [f"{self.dir_manager.bin_dir}/{self.BINARY}", "-f", self.cfg_file]

    def _start_service(self) -> None:
        CommandExecutor.run_background_daemon(self.command, self.start_log_file)

    @staticmethod
    def _wait_http_ready(url: str, ready_fn, name: str) -> None:
        """Poll url until ready_fn(result) is True, then print '<name> started'."""
        print(f"checking {name} ...")
        while True:
            if ready_fn(CommandExecutor.run_http_get_json(url)):
                print(f"{name} started")
                break
            time.sleep(1)

    def _cfg_url(self, path: str = "/stat") -> str:
        port = ConfigFileManager.get_json_data(self.cfg_file)['bind_addr']
        return f"http://127.0.0.1{port}{path}"

    @staticmethod
    def _mkdir_paths(paths) -> None:
        for p in paths:
            Path(p).mkdir(parents=True, exist_ok=True)

    @abstractmethod
    def _check_service(self) -> None:
        raise NotImplementedError


class ServiceConsul(ServiceBase):
    def _setup_service(self) -> None:
        print("starting consul ...")
        self.command = ["/usr/bin/consul", "agent", "-dev", "-client", "0.0.0.0"]

    def _check_service(self) -> None:
        self._wait_http_ready(
            "http://localhost:8500/v1/status/leader",
            lambda r: isinstance(r, str) and r == "127.0.0.1:8300", "consul")


class ServiceKafka(ServiceBase):
    KAFKA_PATH = "/usr/bin/kafka_2.13-3.1.0"

    def _setup_service(self) -> None:
        print("starting kafka ...")
        # format log directories
        if not os.path.exists("/tmp/kraft-combined-logs/meta.properties"):
            cluster_id = CommandExecutor.run([f"{self.KAFKA_PATH}/bin/kafka-storage.sh", "random-uuid"])
            if cluster_id.endswith('\n') or cluster_id.endswith('\r'):
                cluster_id = cluster_id[:-1]
            CommandExecutor.run([f"{self.KAFKA_PATH}/bin/kafka-storage.sh", "format", "-t", cluster_id,
                                 "-c", f"{self.KAFKA_PATH}/config/kraft/server.properties"])
        self.command = [f"{self.KAFKA_PATH}/bin/kafka-server-start.sh", "-daemon",
                        f"{self.KAFKA_PATH}/config/kraft/server.properties"]

    def _check_service(self) -> None:
        print("checking kafka ...")
        cmd = [f"{self.KAFKA_PATH}/bin/kafka-broker-api-versions.sh", "--bootstrap-server", "localhost:9092"]
        while True:
            if CommandExecutor.run_raw(cmd).returncode == 0:
                print("kafka started")
                break
            time.sleep(1)


class ServiceClustermgr(ServiceBase):
    BINARY = "clustermgr"

    def _check_service(self) -> None:
        time.sleep(1)

    @staticmethod
    def check_started() -> None:
        expected = ("StateLeader", "StateReplicate", "StateFollower")

        def ready(r) -> bool:
            if not isinstance(r, dict):
                return False
            rs = r.get('raft_status', {})
            return (rs.get('raftState') or rs.get('raft_state')) in expected

        ServiceBase._wait_http_ready("http://127.0.0.1:9998/stat", ready, "clustermgr")


class ServiceBlobnode(ServiceBase):
    BINARY = "blobnode"

    def _setup_service(self) -> None:
        super()._setup_service()
        self._setup_disks_dir()

    def _check_service(self) -> None:
        self._wait_http_ready(
            self._cfg_url("/stat"),
            lambda r: isinstance(r, list) and len(r) >= 8, self.BINARY)

    def _setup_disks_dir(self) -> None:
        cfg = ConfigFileManager.get_json_data(self.cfg_file)
        self._mkdir_paths(d['path'] for d in cfg['disks'])


class ServiceProxy(ServiceBase):
    BINARY = "proxy"

    # Built-in code mode name to numeric ID mapping.
    # Mirrors the hardcoded constName2CodeMode map in
    # blobstore/common/codemode/codemode.go so that we can resolve mode
    # names to IDs locally without depending on the /volume/codemode/list
    # endpoint (which only exists in the redundancer fork, not in the
    # community CubeFS).
    CODEMODE_NAME_TO_ID: Dict[str, int] = {
        "EC15P12":       1,
        "EC6P6":         2,
        "EC16P20L2":     3,
        "EC6P10L2":      4,
        "EC6P3L3":       5,
        "EC6P6Align0":   6,
        "EC6P6Align512": 7,
        "EC4P4L2":       8,
        "EC12P4":        9,
        "EC16P4":        10,
        "EC3P3":         11,
        "EC10P4":        12,
        "EC6P3":         13,
        "EC12P9":        14,
        "EC24P8":        15,
        "Replica3":      100,
        "Replica3OneAZ": 101,
    }

    def _check_service(self) -> None:
        print("checking proxy ...")
        while True:
            for cm in self._get_enabled_codemodes():
                result = CommandExecutor.run_http_get_json(
                    self._cfg_url(f"/volume/list?code_mode={cm}"))
                if isinstance(result, dict) and 'vids' in result and len(result['vids']) > 0:
                    print("proxy started")
                    return
            time.sleep(1)

    @classmethod
    def _get_enabled_codemodes(cls) -> List[int]:
        """Return the numeric code mode IDs that are enabled in clustermgr.

        Queries /config/get?key=code_mode (available in both community CubeFS
        and redundancer) for the policy list, filters by the enable flag,
        then maps each mode_name to its numeric ID via the local
        CODEMODE_NAME_TO_ID table (mirroring the Go-side
        constName2CodeMode map).
        """
        # /config/get?key=code_mode returns a JSON-encoded string
        # (double-encoded by RespondJSON), so decode twice if needed.
        raw = CommandExecutor.run_http_get_json(
            "http://127.0.0.1:9998/config/get?key=code_mode")
        policies: List[Dict] = []
        if isinstance(raw, str):
            try:
                policies = json.loads(raw)
            except (ValueError, TypeError):
                pass
        elif isinstance(raw, list):
            policies = raw

        return [cls.CODEMODE_NAME_TO_ID[p["mode_name"]]
                for p in policies
                if p.get("enable") and p.get("mode_name") in cls.CODEMODE_NAME_TO_ID]


class ServiceScheduler(ServiceBase):
    BINARY = "scheduler"

    def _check_service(self) -> None:
        self._wait_http_ready(
            self._cfg_url("/stats"),
            lambda r: isinstance(r, dict) and len(r) >= 2, self.BINARY)


class ServiceShardnode(ServiceBase):
    BINARY = "shardnode"

    def _setup_service(self) -> None:
        super()._setup_service()
        self._setup_disks_dir()

    def _check_service(self) -> None:
        expected = ("success_per_min", "failed_per_min")
        self._wait_http_ready(
            self._cfg_url("/blob/delete/stats"),
            lambda r: isinstance(r, dict) and all(k in r for k in expected), self.BINARY)

    def _setup_disks_dir(self) -> None:
        cfg = ConfigFileManager.get_json_data(self.cfg_file)
        self._mkdir_paths(cfg.get("disks_config", {}).get("disks", []))


class ServiceAccess(ServiceBase):
    BINARY = "access"

    def _check_service(self) -> None:
        print("checking access ...")
        time.sleep(1)
        print("access started")


SERVICE_CHOICES = ['all', 'depends', 'blobstore', 'consul', 'kafka',
                   'clustermgr', 'blobnode', 'proxy', 'scheduler', 'access', 'shardnode']


class VstartManager:
    SERVICE_GROUPS = {
        'consul':      {'list_attr': 'services_consul'},
        'kafka':       {'list_attr': 'services_kafka'},
        'clustermgr':  {'list_attr': 'services_clustermgr', 'start_hook': lambda _: ServiceClustermgr.check_started()},
        'blobnode':    {'list_attr': 'services_blobnode'},
        'proxy':       {'list_attr': 'services_proxy'},
        'scheduler':   {'list_attr': 'services_scheduler'},
        'access':      {'list_attr': 'services_access'},
        'shardnode':   {'list_attr': 'services_shardnode'},
    }
    COMPOSITE_SERVICES = {
        'depends':    ['consul', 'kafka'],
        'blobstore':  ['clustermgr', 'blobnode', 'proxy', 'scheduler', 'access'],
    }

    def __init__(self) -> None:
        self.COMPOSITE_SERVICES['all'] = self.COMPOSITE_SERVICES['depends'] + self.COMPOSITE_SERVICES['blobstore']
        self.args = self._parse_args()

    def _is_version_v15(self) -> bool:
        return self.args.version == '1.5.x'

    def _parse_args(self) -> argparse.Namespace:
        parser = argparse.ArgumentParser(description="Vstart Manager for Blobstore")
        parser.add_argument('--version', type=str, default='1.4.x', choices=['1.4.x', '1.5.x'],
                            help='Specify the version of Blobstore')
        parser.add_argument('--az-num', type=str, default='one', choices=['one', 'two', 'three'],
                            help='Number of availability zones to create')
        parser.add_argument('--start', type=str, default='', choices=SERVICE_CHOICES,
                            help='Start specific service by name')
        parser.add_argument('--stop', type=str, default='', choices=SERVICE_CHOICES,
                            help='Stop specific service by name')
        parser.add_argument('--restart', type=str, default='', choices=SERVICE_CHOICES,
                            help='Restart specific service by name')
        parser.add_argument('--rmdir', action='store_true', default=False,
                            help='Remove existing directories before starting services')
        return parser.parse_args()

    def setup_services_default(self) -> None:
        self.services_consul = [
            ServiceConsul(self.args, self.dir_manager, "/usr/bin/consul", "", "consul-start.log"),
        ]
        self.services_kafka = [
            ServiceKafka(self.args, self.dir_manager, "/usr/bin/kafka_2.13-3.1.0", "", "kafka-start.log"),
        ]
        self.services_clustermgr = [
            ServiceClustermgr(self.args, self.dir_manager, "clustermgr1.json", "clustermgr1.json", "clustermgr1-start.log"),
            ServiceClustermgr(self.args, self.dir_manager, "clustermgr2.json", "clustermgr2.json", "clustermgr2-start.log"),
            ServiceClustermgr(self.args, self.dir_manager, "clustermgr3.json", "clustermgr3.json", "clustermgr3-start.log"),
        ]
        self.services_proxy = [
            ServiceProxy(self.args, self.dir_manager, "proxy.json", "proxy.json", "proxy-start.log"),
        ]
        self.services_scheduler = [
            ServiceScheduler(self.args, self.dir_manager, "scheduler.json", "scheduler.json", "scheduler-start.log"),
        ]
        self.services_access = [
            ServiceAccess(self.args, self.dir_manager, "access.json", "access.json", "access-start.log"),
        ]
        self.services_shardnode = []

    def setup_services_one_az(self) -> None:
        self.services_blobnode = [
            ServiceBlobnode(self.args, self.dir_manager, "blobnode.json", "blobnode.json", "blobnode-start.log"),
        ]

    def setup_services_two_az(self) -> None:
        self.services_blobnode = [
            ServiceBlobnode(self.args, self.dir_manager, "blobnode-z0.json", "blobnode-z0.json", "blobnode-z0-start.log"),
            ServiceBlobnode(self.args, self.dir_manager, "blobnode-z1.json", "blobnode-z1.json", "blobnode-z1-start.log"),
        ]

    def setup_services_three_az(self) -> None:
        print("Three AZ setup is not implemented yet.")
        exit(1)

    def setup_services_shardnode(self) -> None:
        self.services_shardnode = [
            ServiceShardnode(self.args, self.dir_manager, "shardnode.json", "shardnode.json", "shardnode-start.log"),
        ]

    def _resolve_groups(self, target: str) -> List[str]:
        """Return the ordered list of service-group names to operate on.

        A composite target expands to its members; a single group wraps as [target].
        """
        if target in self.COMPOSITE_SERVICES:
            return self.COMPOSITE_SERVICES[target]
        if target in self.SERVICE_GROUPS:
            return [target]
        raise ValueError(f"Unknown service: {target}")

    def _start_service_group(self, group_name: str) -> None:
        config = self.SERVICE_GROUPS[group_name]
        services = getattr(self, config['list_attr'])
        for service in services:
            service.run_service()
        hook = config.get('start_hook')
        if hook:
            hook(services)

    def _stop_service_group(self, group_name: str) -> None:
        services = getattr(self, self.SERVICE_GROUPS[group_name]['list_attr'])
        for service in services:
            service.stop_service()

    def _execute_action(self, action: str, target: str) -> None:
        groups = self._resolve_groups(target)
        # stop composite groups in reverse dependency order
        stop_order = reversed(groups) if target in self.COMPOSITE_SERVICES else groups
        if action == 'stop':
            for g in stop_order:
                self._stop_service_group(g)
        elif action == 'start':
            for g in groups:
                self._start_service_group(g)
        elif action == 'restart':
            for g in stop_order:
                self._stop_service_group(g)
            for g in groups:
                self._start_service_group(g)

    def run(self) -> None:
        cfg_dir = f"cfg-{self.args.version}/az-{self.args.az_num}"
        print(f"Using configuration directory: {cfg_dir}")
        self.dir_manager = DirectoryManager(cfg_dir)
        self.dir_manager.setup_directory()

        self.setup_services_default()
        az_setup_map = {
            'one': self.setup_services_one_az,
            'two': self.setup_services_two_az,
            'three': self.setup_services_three_az,
        }
        if self.args.az_num in az_setup_map:
            az_setup_map[self.args.az_num]()
        else:
            print(f"Invalid az-num: {self.args.az_num}")
            exit(1)

        if self._is_version_v15():
            self.setup_services_shardnode()
            self.COMPOSITE_SERVICES['blobstore'].append('shardnode')
            self.COMPOSITE_SERVICES['all'] = self.COMPOSITE_SERVICES['depends'] + self.COMPOSITE_SERVICES['blobstore']

        actions = []
        if self.args.start:
            actions.append(('start', self.args.start))
        if self.args.stop:
            actions.append(('stop', self.args.stop))
        if self.args.restart:
            actions.append(('restart', self.args.restart))
        for action, target in actions:
            self._execute_action(action, target)

        if self.args.rmdir:
            print("Removing all directories...")
            self.dir_manager.remove_directory()


def main():
    if sys.version_info.major < 3:
        print(f"Error: Python 3 or higher is required, but found {sys.version}")
        sys.exit(1)

    VstartManager().run()


if __name__ == "__main__":
    main()
