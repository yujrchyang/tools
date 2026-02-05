#!/usr/bin/env python3
import sys
import argparse
from typing import Any, List, Dict

import common


class HandleService():
    @staticmethod
    def get_vuid_list_from_cm(host: str, disk_id: int) -> List[Dict[str, Any]]:
        url = f"{host}/volume/unit/list?disk_id={disk_id}"
        response_data = common.CommandExecutor.run_http_get_json(url)
        if isinstance(response_data, dict) and "volume_unit_infos" in response_data:
            return response_data["volume_unit_infos"]
        return []

    @staticmethod
    def get_bid_list_from_bn(host: str, disk_id: int, vuid: int, start_bid: int, status: int = 1, count: int = 10) -> tuple[List[Dict[str, Any]], int]:
        url = f"{host}/shard/list/diskid/{disk_id}/vuid/{vuid}/startbid/{start_bid}/status/{status}/count/{count}"
        response_data = common.CommandExecutor.run_http_get_json(url)
        if isinstance(response_data, dict) and "shard_infos" in response_data and "next" in response_data:
            return response_data["shard_infos"], response_data["next"]
        return [], -1

    @staticmethod
    def delete_shard_from_bn(host: str, disk_id: int, vuid: int, bid: int) -> bool:
        url = f"{host}/shard/markdelete/diskid/{disk_id}/vuid/{vuid}/bid/{bid}"
        response = common.CommandExecutor.run_http_post(url)
        if not response:
            return False
        url = f"{host}/shard/delete/diskid/{disk_id}/vuid/{vuid}/bid/{bid}"
        return common.CommandExecutor.run_http_post(url)


class CLI:
    def __init__(self) -> None:
        self.args = self._parse_args()

    def _parse_args(self) -> argparse.Namespace:
        parser = argparse.ArgumentParser(description="Vstart Manager for Blobstore")
        parser.add_argument('--host-cm', type=str, default='http://127.0.0.1:9998', help='Host and port for clustermgr service')
        parser.add_argument('--host-bn', type=str, default='http://127.0.0.1:8899', help='Host and port for blobnode service')
        parser.add_argument('--disk-id', type=int, help='Disk id of the shard to delete')
        parser.add_argument('-n', '--number', type=int, default=1, help='Number of options to process')
        parser.add_argument('--shard-delete', action='store_true', default=False, help='delete shards from blobnode')
        return parser.parse_args()

    def delete_shard(self) -> None:
        if not self.args.disk_id:
            print("Error: --disk-id is required for shard deletion.")
            sys.exit(1)

        print(f"Starting delete shards on disk {self.args.disk_id} ...")
        vols = HandleService.get_vuid_list_from_cm(self.args.host_cm, self.args.disk_id)
        ordered_vols = sorted(vols, key=lambda d: d["free"])
        rows = ordered_vols if self.args.number == -1 else ordered_vols[:self.args.number]
        for vol in rows:
            vuid = vol["vuid"]
            while True:
                start_bid = 0
                shards, next = HandleService.get_bid_list_from_bn(self.args.host_bn, self.args.disk_id, vuid, start_bid)
                for shard in shards:
                    bid = shard["bid"]
                    success = HandleService.delete_shard_from_bn(self.args.host_bn, self.args.disk_id, vuid, bid)
                    if success:
                        print(f"Deleted shard: disk_id={self.args.disk_id}, vuid={vuid}, bid={bid}")
                    else:
                        print(f"Failed to delete shard: disk_id={self.args.disk_id}, vuid={vuid}, bid={bid}")
                if next == 0:
                    break
                else:
                    start_bid = next

    def run(self) -> None:
        if self.args.shard_delete:
            self.delete_shard()


def main():
    if sys.version_info.major < 3:
        print(f"Error: Python 3 or higher is required, but found {sys.version}")
        sys.exit(1)

    CLI().run()

if __name__ == "__main__":
    main()
