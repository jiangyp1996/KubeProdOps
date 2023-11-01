#!/bin/bash



function command_exists ()
{
  command -v "$@" > /dev/null 2>&1
}


# step 01 : check linux kernel version

echo -e "\033[36m[INFO] STEP 01: Check linux kernel version and curl/wget tools...\033[0m"
kernel_version=$(uname -r)
if [ -z "$kernel_version" ]; then
  echo -e "\033[31m[ERROR] Get kernel version error, kernel must be 3.10.0 at minimum\033[0m"
  exit 1
fi

kernel_parts_tmp=(${kernel_version//-/ })
kernel_parts=(${kernel_parts_tmp[0]//./ })
if [ ${kernel_parts[0]} -lt 3 ]; then
  echo -e "\033[31m[ERROR] Kernel version must be 3.10.0 at minimum, current version is ${kernel_parts_tmp[0]}\033[0m"
  exit 1
fi
if [ ${kernel_parts[0]} -eq 3 ] && [ ${kernel_parts[1]} -lt 10 ]; then
  echo -e "\033[31m[ERROR] Kernel version must be 3.10.0 at minimum, current version is ${kernel_parts_tmp[0]}\033[0m"
  exit 1
fi
echo -e "\033[32m[OK] Check kernel OK, current kernel version is ${kernel_parts_tmp[0]}\033[0m"


# step 02 : check parameters


# step 03 : check hostname



