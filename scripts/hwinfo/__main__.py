import subprocess
import argparse
import json


class HardwareInfo:
    def __init__(self):
        self.hw_info = ["lshw", "-json"]
        self.pci_info = ["lspci", "-vmm"]
        self.cpu_info = ["lscpu", "-J"]
        self.blk_info = ["lsblk", "-J"]
        self.ipls_info = ["ip", "-json", "link", "show"]
        self.ipas_info = ["ip", "-json", "addr", "show"]

    def _get_info(self, command):
        try:
            result = subprocess.run(command, capture_output=True, text=True, check=True)
            return result.stdout
        except FileNotFoundError:
            return (
                f"{command[0]} command not found. Please install the required package."
            )
        except subprocess.CalledProcessError as e:
            return f"An error occurred while running {command[0]}: {e}"

    def parse_lscpiu_output(self, output):
        devices = []
        current_device = {}
        for line in output.splitlines():
            line = line.strip()
            if not line:
                if current_device:
                    devices.append(current_device)
                    current_device = {}
                continue
            if ":" in line:
                key, value = line.split(":", 1)
                current_device[key.strip()] = value.strip()
        if current_device:
            devices.append(current_device)
        return json.dumps(devices)

    def get_hw_info(self):
        hw_info = self._get_info(self.hw_info)
        pci_info = self.parse_lscpiu_output(self._get_info(self.pci_info))
        cpu_info = self._get_info(self.cpu_info)
        blk_info = self._get_info(self.blk_info)
        ipls_info = self._get_info(self.ipls_info)
        ipas_info = self._get_info(self.ipas_info)

        combined_info = {
            "Hardware Information": json.loads(hw_info),
            "PCI Information": json.loads(pci_info),
            "CPU Information": json.loads(cpu_info),
            "Block Device Information": json.loads(blk_info),
            "IP Network Device Information": json.loads(ipls_info),
            "IP Address Information": json.loads(ipas_info),
        }
        return combined_info


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Get hardware information")
    parser.add_argument(
        "--output", type=str, help="Output file to save hardware information"
    )
    parser.add_argument(
        "--refresh", action="store_true", help="Refresh hardware information"
    )
    args = parser.parse_args()

    hwinfo = HardwareInfo()
    info = hwinfo.get_hw_info()
    for key, value in info.items():
        print(f"{key}:\n{json.dumps(value, indent=4)}\n")
        with open(f"out/{key.replace(' ', '_').lower()}.json", "w") as f:
            f.write(json.dumps(value, indent=4))
    # with open("out/hwinfo_output.json", "w") as f:
    #     f.write(json.dumps(info, indent=4))
    # print(info)
