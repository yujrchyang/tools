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
        self.bin_dir = os.path.abspath(os.path.join(VSTART_SCRIPT_DIR, '../../build/bin/blobstore'))
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
        for pid in glob.glob("/proc/[0-9]*"):
            try:
                if self.process_identifier in open(f"{pid}/cmdline").read().replace("\0", " "):
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
            CommandExecutor.run([f"{kafka_path}/bin/kafka-storage.sh", "format", "-t", cluster_id,
                                 "-c", f"{kafka_path}/config/kraft/server.properties"])
        self.command = [f"{kafka_path}/bin/kafka-server-start.sh", "-daemon",
                        f"{kafka_path}/config/kraft/server.properties"]

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
            if isinstance(result, list) and len(result) >= 8:
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
        codemode = 11
        if self.args.az_num == 'two':
            codemode = 4
        url = f"http://127.0.0.1{port}/volume/list?code_mode={codemode}"
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
    SERVICE_GROUPS = {
        'consul':      {'list_attr': 'services_consul'},
        'kafka':       {'list_attr': 'services_kafka'},
        'clustermgr':  {'list_attr': 'services_clustermgr', 'start_hook': lambda _: ServiceClustermgr.check_started()},
        'blobnode':    {'list_attr': 'services_blobnode'},
        'proxy':       {'list_attr': 'services_proxy'},
        'scheduler':   {'list_attr': 'services_scheduler'},
        'access':      {'list_attr': 'services_access'},
    }
    COMPOSITE_SERVICES = {
        'depends':    ['consul', 'kafka'],
        'blobstore':  ['clustermgr', 'blobnode', 'proxy', 'scheduler', 'access'],
        'all':        ['consul', 'kafka', 'clustermgr', 'blobnode', 'proxy', 'scheduler', 'access'],
    }

    def __init__(self) -> None:
        self.args = self._parse_args()

    def _parse_args(self) -> argparse.Namespace:
        parser = argparse.ArgumentParser(description="Vstart Manager for Blobstore")
        parser.add_argument('--version', type=str, default='1.4.x', choices=['1.4.x', '1.5.x'],
                            help='Specify the version of Blobstore')
        parser.add_argument('--az-num', type=str, default='one', choices=['one', 'two', 'three'],
                            help='Number of availability zones to create')
        parser.add_argument('--start', type=str, default='',
                            choices=['all', 'depends', 'blobstore', 'consul', 'kafka',
                                     'clustermgr', 'blobnode', 'proxy', 'scheduler', 'access'],
                            help='Start specific service by name')
        parser.add_argument('--stop', type=str, default='',
                            choices=['all', 'depends', 'blobstore', 'consul', 'kafka',
                                     'clustermgr', 'blobnode', 'proxy', 'scheduler', 'access'],
                            help='Stop specific service by name')
        parser.add_argument('--restart', type=str, default='',
                            choices=['all', 'depends', 'blobstore', 'consul', 'kafka',
                                     'clustermgr', 'blobnode', 'proxy', 'scheduler', 'access'],
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

    def _start_service_group(self, group_name: str) -> None:
        config = self.SERVICE_GROUPS[group_name]
        services = getattr(self, config['list_attr'])
        for service in services:
            service.run_service()
        hook = config.get('start_hook')
        if hook:
            hook(services)

    def _stop_service_group(self, group_name: str) -> None:
        config = self.SERVICE_GROUPS[group_name]
        services = getattr(self, config['list_attr'])
        for service in services:
            service.stop_service()

    def _start_composite(self, name: str) -> None:
        for svc in self.COMPOSITE_SERVICES[name]:
            self._start_service_group(svc)

    def _stop_composite(self, name: str) -> None:
        for svc in reversed(self.COMPOSITE_SERVICES[name]):
            self._stop_service_group(svc)

    def _execute_action(self, action: str, target: str) -> None:
        if target in self.COMPOSITE_SERVICES:
            if action == 'start':
                self._start_composite(target)
            elif action == 'stop':
                self._stop_composite(target)
            elif action == 'restart':
                self._stop_composite(target)
                self._start_composite(target)
        elif target in self.SERVICE_GROUPS:
            if action == 'start':
                self._start_service_group(target)
            elif action == 'stop':
                self._stop_service_group(target)
            elif action == 'restart':
                self._stop_service_group(target)
                self._start_service_group(target)
        else:
            raise ValueError(f"Unknown service: {target}")

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
