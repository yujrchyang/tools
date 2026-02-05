#!/usr/bin/env python3
import sys
import argparse
import json
from typing import Any, List, Dict

import common

if sys.version_info < (3, 10):
    sys.exit(f"Error: Python 3.10 or higher is required, but found {sys.version}")

class HandleService():
    @staticmethod
    def get_disk_host_from_cm(host: str, disk_id: int) -> str:
        url = f"{host}/disk/info?disk_id={disk_id}"
        response_data = common.CommandExecutor.run_http_get_json(url)
        if isinstance(response_data, dict) and "host" in response_data:
            return response_data["host"]
        sys.exit(f"don't get disk {disk_id} info from {host}")

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
    def get_disk_list_from_cm(host: str, marker: int, count: int = 10) -> tuple[List[Dict[str, Any]], int]:
        url = f"{host}/disk/list?marker={marker}&count={count}"
        response_data = common.CommandExecutor.run_http_get_json(url)
        if isinstance(response_data, dict) and "disks" in response_data and "marker" in response_data:
            return response_data["disks"], response_data["marker"]
        return [], -1

    @staticmethod
    def get_sc_stat(host: str, task: str = "all") -> Dict[str, Any]:
        url = f"{host}/stats"
        response_data = common.CommandExecutor.run_http_get_json(url)
        if not isinstance(response_data, dict):
            return {}
        if task == "all":
            return response_data
        else:
            if f"{task}" not in response_data:
                return {}
            return response_data[f"{task}"]

    @staticmethod
    def get_cm_stat(host: str) -> Dict[str, Any]:
        url = f"{host}/stat"
        response_data = common.CommandExecutor.run_http_get_json(url)
        if not isinstance(response_data, dict):
            return {}
        return response_data

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
        parser.add_argument('--host-sc', type=str, default='http://127.0.0.1:9800', help='Host and port for scheduler service')
        parser.add_argument('--disk-id', type=int, help='Disk id of the shard to delete')
        parser.add_argument('-n', '--number', type=int, default=1, help='Number of options to process')
        parser.add_argument('--shard-delete', action='store_true', default=False, help='Delete shards from blobnode')
        parser.add_argument('--disk-list', action='store_true', default=False, help='List all disk from clustermgr')
        parser.add_argument('--show', type=str, choices=['scstat', 'cmstat'], help='Show specify info')
        parser.add_argument('--task', type=str, default='all',
                            choices=['all', 'disk_repair', 'disk_drop', 'balance', 'manual_migrate',
                                     'volume_inspect', 'shard_repair', 'blob_delete'],
                            help='Task which you want operate')
        return parser.parse_args()

    def delete_shard(self) -> None:
        if not self.args.disk_id:
            print("Error: --disk-id is required for shard deletion.")
            sys.exit(1)

        print(f"Starting delete shards on disk {self.args.disk_id} ...")
        # get disk host
        disk_host = HandleService.get_disk_host_from_cm(self.args.host_cm, self.args.disk_id)
        # get volume info
        vols = HandleService.get_vuid_list_from_cm(self.args.host_cm, self.args.disk_id)
        ordered_vols = sorted(vols, key=lambda d: d["free"])
        rows = ordered_vols if self.args.number == -1 else ordered_vols[:self.args.number]
        for vol in rows:
            vuid = vol["vuid"]
            while True:
                start_bid = 0
                shards, next = HandleService.get_bid_list_from_bn(disk_host, self.args.disk_id, vuid, start_bid)
                for shard in shards:
                    bid = shard["bid"]
                    success = HandleService.delete_shard_from_bn(disk_host, self.args.disk_id, vuid, bid)
                    if success:
                        print(f"Deleted shard: disk_id={self.args.disk_id}, vuid={vuid}, bid={bid}")
                    else:
                        print(f"Failed to delete shard: disk_id={self.args.disk_id}, vuid={vuid}, bid={bid}")
                if next == 0 or next == -1:
                    break
                else:
                    start_bid = next

    def disk_list(self) -> None:
        try:
            from prettytable import PrettyTable
        except ImportError:
            print("Error: prettytable library is not installed.")
            print("Please install it using: pip install prettytable")
            sys.exit(1)

        table = PrettyTable()
        table.field_names = ["IDC", "Rack", "Host", "Path", "Status", "Readonly", "DiskSetID",
                             "NodeID", "DiskID", "Used", "Free", "Size", "MaxChk", "FreeChk", "UsedChk"]
        marker = 0
        all_disks = []
        while True:
            disks, marker = HandleService.get_disk_list_from_cm(self.args.host_cm, marker)
            all_disks.extend(disks)
            if marker == -1 or marker == 0:
                break

        sorted_all_disks = sorted(all_disks, key=lambda x: (x.get('idc', ''),
                                                            x.get('rack', ''),
                                                            x.get('host', ''),
                                                            x.get('disk_id', 0)))
        for disk in sorted_all_disks:
            idc = disk.get("idc", "")
            rock = disk.get("rack", "")
            host = disk.get("host", "")
            path = disk.get("path", "")
            status = common.HumanReadable.human_disk_stats(disk.get("status", -1))
            readonly = disk.get("readonly", "")
            disk_set_id = disk.get("disk_set_id", "")
            node_id = disk.get("node_id", "")
            disk_id = disk.get("disk_id", "")
            used = common.HumanReadable.human_bytes(disk.get("used", 0))
            free = common.HumanReadable.human_bytes(disk.get("free", 0))
            size = common.HumanReadable.human_bytes(disk.get("size", 0))
            max_chunk_cnt = disk.get("max_chunk_cnt", 0)
            free_chunk_cnt = disk.get("free_chunk_cnt", 0)
            used_chunk_cnt = disk.get("used_chunk_cnt", 0)
            table.add_row([idc, rock, host, path, status, readonly, disk_set_id, node_id, disk_id,
                           used, free, size, max_chunk_cnt, free_chunk_cnt, used_chunk_cnt])
        print(table)

    def show_scheduler_stat(self) -> None:
        result = HandleService.get_sc_stat(self.args.host_sc, self.args.task)
        print(json.dumps(result, indent=2))

    def show_clustermgr_stat(self) -> None:
        result = HandleService.get_cm_stat(self.args.host_cm)
        print(json.dumps(result, indent=2))

    def run(self) -> None:
        if self.args.shard_delete:
            self.delete_shard()
        if self.args.disk_list:
            self.disk_list()
        if self.args.show:
            if self.args.show == 'scstat':
                self.show_scheduler_stat()
            elif self.args.show == 'cmstat':
                self.show_clustermgr_stat()

def main():
    CLI().run()

if __name__ == "__main__":
    main()
