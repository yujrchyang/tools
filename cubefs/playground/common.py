import os
import sys
import json
import subprocess
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError
from typing import Union, Any, List, Dict

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

    @staticmethod
    def run_http_post(url: str, timeout=5) -> bool:
        try:
            req = Request(url=url, method='POST')
            with urlopen(req, timeout=timeout) as response:
                return response.status == 200
        except (URLError, HTTPError, TimeoutError, UnicodeDecodeError, AttributeError):
            pass
        return False

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
