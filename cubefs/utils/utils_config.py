#!/usr/bin/env python3
import sys
import json
from typing import Dict

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
