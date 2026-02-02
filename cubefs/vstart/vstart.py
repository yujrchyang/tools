#!/usr/bin/env python3
import os
import re
import sys
import json
import argparse
import subprocess
import shutil
import time
import signal
import glob
from urllib.request import urlopen
from urllib.error import URLError, HTTPError
from pathlib import Path
from typing import Union, Any, List, Dict
from abc import ABC, abstractmethod


class CommandExecutor:
    """Command execution tool class, encapsulating subprocess calls and error handling"""

    @staticmethod
    def _get_run_kwargs(capture_output: bool) -> Dict[str, Any]:
        if sys.version_info >= (3, 7):
            text_mode = {"text": True}
        else:
            text_mode = {"universal_newlines": True}
        kwargs = {
            "shell": False,
            "stdout": subprocess.PIPE if capture_output else None,
            "stderr": subprocess.PIPE if capture_output else None,
            **text_mode
        }
        return kwargs

    @staticmethod
    def run(command: List[str], capture_output: bool = True) -> str:
        """
        Execute a shell command and return its standard output.
        Raises CalledProcessError if the command returns a non-zero exit status.
        """
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
        """
        Execute a shell command directly and return the raw result without exception handling.
        Always captures both stdout and stderr.
        """
        return subprocess.run(
            command,
            check=False,
            **CommandExecutor._get_run_kwargs(True)
        )

    @staticmethod
    def run_foreground_daemon(command: List[str], extra_env: Dict[str, str]) -> None:
        # Start the daemon process in the foreground
        try:
            env = os.environ.copy()
            if extra_env:
                env.update(extra_env)

            subprocess.run(
                command,
                stdout=sys.stdout,  # Output to container standard output
                stderr=sys.stderr,  # Errors are output to the container's standard error
                env=env,            # Specify more env
                check=True          # Throws an exception when the daemon exits
            )
        except subprocess.CalledProcessError as e:
            print(f"the daemon process exited abnormally, error code : {e.returncode}")
            sys.exit(e.returncode)
        except Exception as e:
            print(f"failed to start the daemon process : {str(e)}")
            sys.exit(1)

    @staticmethod
    def run_background_daemon(command: List[str], logfile: str):
        # Start the daemon process in the background
        pid = os.fork()
        if pid > 0:
            return pid

        # detach from the terminal
        os.setsid()
        # Second fork to prevent reacquisition of tty
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
    def run_test(command: List[str]) -> None:
        print(f"Running test command: {' '.join(command)}")

    @staticmethod
    def run_http_get_json(url: str, timeout=5) -> Union[Dict[str, Any], List[Any]]:
        try:
            with urlopen(url, timeout=timeout) as response:
                if response.status != 200:
                    return {}
                body = response.read().decode('utf-8')
                return json.loads(body)
        except (URLError, HTTPError, TimeoutError, ValueError, UnicodeDecodeError, AttributeError):
            pass
        return {}


class DirectoryManager:
    def __init__(self, cfg_dir: str) -> None:
        VSTART_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
        self.bin_dir = os.path.abspath(os.path.join(VSTART_SCRIPT_DIR, '../build/bin/blobstore'))
        self.lib_dir = os.path.abspath(os.path.join(VSTART_SCRIPT_DIR, './run/lib'))
        self.log_dir = os.path.abspath(os.path.join(VSTART_SCRIPT_DIR, './run/log'))
        self.cfg_dir = os.path.abspath(os.path.join(VSTART_SCRIPT_DIR, cfg_dir))
        self.all_dirs = [self.lib_dir, self.log_dir]

    @staticmethod
    def is_directory_empty(path) -> bool:
        if not os.path.exists(path):
            return True
        if not os.path.isdir(path):
            print(f"input path {path} is not a directory.")
            sys.exit(1)
        return len(os.listdir(path)) == 0

    @staticmethod
    def get_files_by_prefix(directory, prefix) -> List[str]:
        return [
            os.path.join(directory, filename)
            for filename in os.listdir(directory)
            if filename.startswith(prefix)
        ]

    @staticmethod
    def natural_sort_keys(s):
        return [int(text) if text.isdigit() else text.lower()
                for text in re.split(r'(\d+)', s)]

    def setup_directory(self) -> None:
        for dir in self.all_dirs:
            dir_path = Path(dir)
            dir_path.mkdir(parents=True, exist_ok=True)

    def remove_directory(self) -> None:
        for dir in self.all_dirs:
            dir_path = Path(dir)
            if dir_path.exists():
                shutil.rmtree(dir_path)


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


class ServiceBase(ABC):
    def __init__(self, dir_manager: DirectoryManager, service_name: str, cfg_file: str, start_log_file: str) -> None:
        self.dir_manager = dir_manager
        self.service_name = service_name
        self.cfg_file = f"{self.dir_manager.cfg_dir}/{cfg_file}"
        self.start_log_file = f"{self.dir_manager.log_dir}/{start_log_file}"
        self.command: List[str] = []

    def run_service(self) -> None:
        self._setup_service()
        self._start_service()
        self._check_service()

    def stop_service(self) -> None:
        print(f"stopping {self.service_name} ...")
        for pid in glob.glob("/proc/[0-9]*"):
            try:
                if self.service_name in open(f"{pid}/cmdline").read().replace("\0", " "):
                    os.kill(int(pid.split("/")[-1]), signal.SIGKILL)
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                pass

    @abstractmethod
    def _setup_service(self) -> None:
        raise NotImplementedError

    @abstractmethod
    def _check_service(self) -> None:
        raise NotImplementedError

    def _start_service(self) -> None:
        CommandExecutor.run_background_daemon(self.command, self.start_log_file)

class ServiceConsul(ServiceBase):
    def _setup_service(self) -> None:
        print("starting consul ...")
        self.command = ["/usr/bin/consul", "agent", "-dev", "-client", "0.0.0.0"]

    def _check_service(self) -> None:
        print("checking consul ...")
        url = "http://localhost:8500/v1/status/leader"
        while True:
            result = CommandExecutor.run_http_get_json(url)
            if isinstance(result, str) and result == "127.0.0.1:8300":
                print("consul started")
                break
            time.sleep(1)

class ServiceKafka(ServiceBase):
    def _setup_service(self) -> None:
        print("starting kafka ...")
        kafka_path = "/usr/bin/kafka_2.13-3.1.0"
        # format log directories
        formatted_file = "/tmp/kraft-combined-logs/meta.properties"
        if not os.path.exists(formatted_file):
            cluster_id = CommandExecutor.run([f"{kafka_path}/bin/kafka-storage.sh", "random-uuid"])
            if cluster_id.endswith('\n') or cluster_id.endswith('\r'):
                cluster_id = cluster_id[:-1]
            CommandExecutor.run([f"{kafka_path}/bin/kafka-storage.sh", "format", "-t", cluster_id, "-c", f"{kafka_path}/config/kraft/server.properties"])
        self.command = [f"{kafka_path}/bin/kafka-server-start.sh", "-daemon", f"{kafka_path}/config/kraft/server.properties"]

    def _check_service(self) -> None:
        print("checking kafka ...")
        kafka_path = "/usr/bin/kafka_2.13-3.1.0"
        cmd = [f"{kafka_path}/bin/kafka-broker-api-versions.sh", "--bootstrap-server", "localhost:9092"]
        while True:
            res = CommandExecutor.run_raw(cmd)
            if res.returncode == 0:
                print("kafka started")
                break
            time.sleep(1)

class ServiceClustermgr(ServiceBase):
    def _setup_service(self) -> None:
        print("starting clustermgr ...")
        self.command = [f"{self.dir_manager.bin_dir}/clustermgr", "-f", self.cfg_file]

    def _check_service(self) -> None:
        time.sleep(1)

    @staticmethod
    def check_started() -> None:
        print("checking clustermgr ...")
        url = "http://127.0.0.1:9998/stat"
        expected_states=("StateLeader", "StateReplicate", "StateFollower")
        while True:
            result = CommandExecutor.run_http_get_json(url)
            if isinstance(result, dict):
                raft_state = result.get('raft_status', {}).get('raftState')
                if raft_state in expected_states:
                    print("clustermgr started")
                    break
            time.sleep(1)

class ServiceBlobnode(ServiceBase):
    def _setup_service(self) -> None:
        print("starting blobnode ...")
        self._setup_disks_dir()
        self.command = [f"{self.dir_manager.bin_dir}/blobnode", "-f", self.cfg_file]

    def _check_service(self) -> None:
        print("checking blobnode ...")
        blobnode_config = ConfigFileManager.get_json_data(self.cfg_file)
        port = blobnode_config['bind_addr']
        url = f"http://127.0.0.1{port}/stat"
        while True:
            result = CommandExecutor.run_http_get_json(url)
            if isinstance(result, list) and len(result) == 8:
                print("blobnode started")
                break
            time.sleep(1)

    def _setup_disks_dir(self) -> None:
        blobnode_config = ConfigFileManager.get_json_data(self.cfg_file)
        for disk in blobnode_config['disks']:
            disk_path = Path(disk['path'])
            disk_path.mkdir(parents=True, exist_ok=True)

class ServiceProxy(ServiceBase):
    def _setup_service(self) -> None:
        print("starting proxy ...")
        self.command = [f"{self.dir_manager.bin_dir}/proxy", "-f", self.cfg_file]

    def _check_service(self) -> None:
        print("checking proxy ...")
        proxy_config = ConfigFileManager.get_json_data(self.cfg_file)
        port = proxy_config['bind_addr']
        url = f"http://127.0.0.1{port}/volume/list?code_mode=11"
        while True:
            result = CommandExecutor.run_http_get_json(url)
            if isinstance(result, dict) and 'vids' in result and len(result['vids']) > 0:
                print("proxy started")
                break
            time.sleep(1)

class ServiceScheduler(ServiceBase):
    def _setup_service(self) -> None:
        print("starting scheduler ...")
        self.command = [f"{self.dir_manager.bin_dir}/scheduler", "-f", self.cfg_file]

    def _check_service(self) -> None:
        print("checking scheduler ...")
        scheduler_config = ConfigFileManager.get_json_data(self.cfg_file)
        port = scheduler_config['bind_addr']
        url = f"http://127.0.0.1{port}/stats"
        while True:
            result = CommandExecutor.run_http_get_json(url)
            if isinstance(result, dict) and len(result) >= 2:
                print("scheduler started")
                break
            time.sleep(1)

class ServiceShardnode(ServiceBase):
    def _setup_service(self) -> None:
        print("starting shardnode ...")
        self._setup_disks_dir()
        self.command = [f"{self.dir_manager.bin_dir}/shardnode", "-f", self.cfg_file]

    def _check_service(self) -> None:
        print("checking shardnode ...")
        shardnode_config = ConfigFileManager.get_json_data(self.cfg_file)
        port = shardnode_config['bind_addr']
        url = f"http://127.0.0.1{port}/blob/delete/stats"
        expected_keys=("success_per_min", "failed_per_min")
        while True:
            result = CommandExecutor.run_http_get_json(url)
            if isinstance(result, dict) and all(key in result for key in expected_keys):
                print("shardnode started")
                break
            time.sleep(1)

    def _setup_disks_dir(self) -> None:
        shardnode_config = ConfigFileManager.get_json_data(self.cfg_file)
        disks = shardnode_config.get("disks_config", {}).get("disks", [])
        for disk_path in disks:
            Path(disk_path).mkdir(parents=True, exist_ok=True)

class ServiceAccess(ServiceBase):
    def _setup_service(self) -> None:
        print("starting access ...")
        self.command = [f"{self.dir_manager.bin_dir}/access", "-f", self.cfg_file]

    def _check_service(self) -> None:
        print("checking access ...")
        time.sleep(1)
        print("access started")


class VstartManager:
    def __init__(self) -> None:
        self.args = self._parse_args()

    def _parse_args(self) -> argparse.Namespace:
        parser = argparse.ArgumentParser(description="Vstart Manager for Blobstore")
        parser.add_argument('--version', type=str, default='1.4.x', choices=['1.4.x', '1.5.x'], help='Specify the version of Blobstore')
        parser.add_argument('--az-num', type=str, default='one', choices=['one', 'two', 'three'], help='Number of availability zones to create')
        parser.add_argument('--rmdir', action='store_true', default=False, help='Remove existing directories before starting services')
        parser.add_argument('--start-depends', action='store_true', default=False, help='Start dependent services like Consul and Kafka')
        parser.add_argument('--stop-depends', action='store_true', default=False, help='Stop dependent services like Consul and Kafka')
        parser.add_argument('--restart-depends', action='store_true', default=False, help='Restart dependent services like Consul and Kafka')
        parser.add_argument('--start-blobstore', action='store_true', default=False, help='Start all Blobstore services')
        parser.add_argument('--stop-blobstore', action='store_true', default=False, help='Stop all Blobstore services')
        parser.add_argument('--restart-blobstore', action='store_true', default=False, help='Restart all Blobstore services')
        parser.add_argument('--start-clustermgr', action='store_true', default=False, help='Start clustermgr services only')
        parser.add_argument('--stop-clustermgr', action='store_true', default=False, help='Stop clustermgr services only')
        parser.add_argument('--restart-clustermgr', action='store_true', default=False, help='Restart clustermgr services only')
        parser.add_argument('--start-blobnode', action='store_true', default=False, help='Start blobnode services only')
        parser.add_argument('--stop-blobnode', action='store_true', default=False, help='Stop blobnode services only')
        parser.add_argument('--restart-blobnode', action='store_true', default=False, help='Restart blobnode services only')
        parser.add_argument('--start-proxy', action='store_true', default=False, help='Start proxy services only')
        parser.add_argument('--stop-proxy', action='store_true', default=False, help='Stop proxy services only')
        parser.add_argument('--restart-proxy', action='store_true', default=False, help='Restart proxy services only')
        parser.add_argument('--start-scheduler', action='store_true', default=False, help='Start scheduler services only')
        parser.add_argument('--stop-scheduler', action='store_true', default=False, help='Stop scheduler services only')
        parser.add_argument('--restart-scheduler', action='store_true', default=False, help='Restart scheduler services only')
        parser.add_argument('--start-access', action='store_true', default=False, help='Start access services only')
        parser.add_argument('--stop-access', action='store_true', default=False, help='Stop access services only')
        parser.add_argument('--restart-access', action='store_true', default=False, help='Restart access services only')
        return parser.parse_args()

    def setup_services_one_az(self) -> None:
        self.services_depends = [
            ServiceConsul(self.dir_manager, "/usr/bin/consul", "", "consul-start.log"),
            ServiceKafka(self.dir_manager, "/usr/bin/kafka_2.13-3.1.0", "", "kafka-start.log"),
        ]
        self.services_clustermgr = [
            ServiceClustermgr(self.dir_manager, "clustermgr1.json", "clustermgr1.json", "clustermgr1-start.log"),
            ServiceClustermgr(self.dir_manager, "clustermgr2.json", "clustermgr2.json", "clustermgr2-start.log"),
            ServiceClustermgr(self.dir_manager, "clustermgr3.json", "clustermgr3.json", "clustermgr3-start.log"),
        ]
        self.services_blobnode = [
            ServiceBlobnode(self.dir_manager, "blobnode.json", "blobnode.json", "blobnode-start.log"),
        ]
        self.services_proxy = [
            ServiceProxy(self.dir_manager, "proxy.json", "proxy.json", "proxy-start.log"),
        ]
        self.services_scheduler = [
            ServiceScheduler(self.dir_manager, "scheduler.json", "scheduler.json", "scheduler-start.log"),
        ]
        self.services_access = [
            ServiceAccess(self.dir_manager, "access.json", "access.json", "access-start.log"),
        ]

    def setup_services_two_az(self) -> None:
        print("Two AZ setup is not implemented yet.")
        exit(1)

    def setup_services_three_az(self) -> None:
        print("Three AZ setup is not implemented yet.")
        exit(1)

    def start_depends(self) -> None:
        print("Starting dependent services...")
        for service in self.services_depends:
                service.run_service()

    def stop_depends(self) -> None:
        print("Stopping dependent services...")
        for service in reversed(self.services_depends):
                service.stop_service()

    def start_clustermgr(self) -> None:
        for idx, service in enumerate(self.services_clustermgr):
            service.run_service()
            if idx == len(self.services_clustermgr) - 1:
                ServiceClustermgr.check_started()

    def stop_clustermgr(self) -> None:
        for service in reversed(self.services_clustermgr):
            service.stop_service()

    def start_blobnode(self) -> None:
        for service in self.services_blobnode:
            service.run_service()

    def stop_blobnode(self) -> None:
        for service in reversed(self.services_blobnode):
            service.stop_service()

    def start_proxy(self) -> None:
        for service in self.services_proxy:
            service.run_service()

    def stop_proxy(self) -> None:
        for service in reversed(self.services_proxy):
            service.stop_service()

    def start_scheduler(self) -> None:
        for service in self.services_scheduler:
            service.run_service()

    def stop_scheduler(self) -> None:
        for service in reversed(self.services_scheduler):
            service.stop_service()

    def start_access(self) -> None:
        for service in self.services_access:
            service.run_service()

    def stop_access(self) -> None:
        for service in reversed(self.services_access):
            service.stop_service()

    def run(self) -> None:
        cfg_dir = f"cfg-{self.args.version}/az-{self.args.az_num}"
        print(f"Using configuration directory: {cfg_dir}")
        self.dir_manager = DirectoryManager(cfg_dir)
        self.dir_manager.setup_directory()

        if self.args.az_num == 'one':
            self.setup_services_one_az()
        elif self.args.az_num == 'two':
            self.setup_services_two_az()
        elif self.args.az_num == 'three':
            self.setup_services_three_az()
        else:
            print(f"Invalid az-num: {self.args.az_num}")
            exit(1)

        if self.args.start_depends:
            self.start_depends()
        if self.args.stop_depends:
            self.stop_depends()
        if self.args.restart_depends:
            self.stop_depends()
            self.start_depends()

        if self.args.start_blobstore:
            self.start_clustermgr()
            self.start_blobnode()
            self.start_proxy()
            self.start_scheduler()
            self.start_access()
        if self.args.stop_blobstore:
            self.stop_access()
            self.stop_scheduler()
            self.stop_proxy()
            self.stop_blobnode()
            self.stop_clustermgr()
        if self.args.restart_blobstore:
            self.stop_access()
            self.stop_scheduler()
            self.stop_proxy()
            self.stop_blobnode()
            self.stop_clustermgr()
            self.start_clustermgr()
            self.start_blobnode()
            self.start_proxy()
            self.start_scheduler()
            self.start_access()

        if self.args.start_clustermgr:
            self.start_clustermgr()
        if self.args.stop_clustermgr:
            self.stop_clustermgr()
        if self.args.restart_clustermgr:
            self.stop_clustermgr()
            self.start_clustermgr()

        if self.args.start_blobnode:
            self.start_blobnode()
        if self.args.stop_blobnode:
            self.stop_blobnode()
        if self.args.restart_blobnode:
            self.stop_blobnode()
            self.start_blobnode()

        if self.args.start_proxy:
            self.start_proxy()
        if self.args.stop_proxy:
            self.stop_proxy()
        if self.args.restart_proxy:
            self.stop_proxy()
            self.start_proxy()

        if self.args.start_scheduler:
            self.start_scheduler()
        if self.args.stop_scheduler:
            self.stop_scheduler()
        if self.args.restart_scheduler:
            self.stop_scheduler()
            self.start_scheduler()

        if self.args.start_access:
            self.start_access()
        if self.args.stop_access:
            self.stop_access()
        if self.args.restart_access:
            self.stop_access()
            self.start_access()

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
