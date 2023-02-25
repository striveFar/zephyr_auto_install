#!/bin/bash

CMAKE_MIN_VERSION="3.20.0"
PYTHON_MIN_VERSION="3.8"
DTC_MIN_VERSION="1.4.6"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

ask_yn()
{
  local reply

  while true; do
    read -r -p "$1 [y/n]? " reply

    case "${reply}" in
      Y* | y*)  return 0 ;;
      N* | n*)  return 1 ;;
      *)        echo "Invalid choice '${reply}'" ;;
    esac
  done
}

# 获取当前Ubuntu操作系统版本号
ubuntu_version=$(lsb_release -rs)

# 判断当前版本号是否大于等于20.04
if [ "$(printf '%s\n' "$ubuntu_version" "20.04" | sort -V | head -n 1)" = "20.04" ]; then
	echo "Welcome to use the Zephyr environment deployment script!"
	if [ "$(printf '%s\n' "$ubuntu_version" "22.04" | sort -V | tail -n 1)" = "22.04" ]; then
		echo "Auto download Kitware: The current Ubuntu version is $ubuntu_version"
		# Check if kitware-archive.sh exists
		if [ ! -f "kitware-archive.sh" ]; then
			# Download and run kitware-archive.sh
			echo "The current Ubuntu version is $ubuntu_version"
			echo "您的 Ubuntu 版本较旧，将为您下载并安装 Kitware 存储库。"
			wget https://apt.kitware.com/kitware-archive.sh
			sudo bash kitware-archive.sh
		fi

	fi
else
	echo "The current Ubuntu version is $ubuntu_version, which is too low for Zephyr environment deployment."
fi


# 检查参数数量是否正确            
if [ $# -ne 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
	echo "Usage: $0 /path/to/your_project_name"
	echo "Use -h or --help option to see this help message."
	exit 1                        
fi                                

zephyr_project_path=$1            

if [ -d "$zephyr_project_path" ]; then
	echo -e "${GREEN}Folder already exists.${NC}"
else
    ask_yn "NOTE: folder doesn't exist, create?"
    if [ $? == 0 ]; then
	mkdir "$zephyr_project_path"
	echo -e "${GREEN}Now, folder has been created: $zephyr_project_path${NC}"
    else
	exit 1                        
    fi
fi


source_venv() {
	if [ ! -d "$zephyr_project_path/.venv" ]; then
		echo "Create a new virtual environment:"
		export LC_ALL=C
		export LANG=C
		python3 -m venv $zephyr_project_path/.venv
	fi

	if [ "$1" = "dot" ]; then
		# 点命令会在当前终端中激活Python虚拟环境，而不是在子shell中运行
		. "$zephyr_project_path/.venv/bin/activate"
	else
		source "$zephyr_project_path/.venv/bin/activate"
	fi

    # 激活成功则返回0，否则返回非0值
    return $?
}

sudo apt update -y
sudo apt upgrade -y

sudo apt install -y --no-install-recommends git cmake ninja-build gperf \
	ccache dfu-util device-tree-compiler wget \
	python3-dev python3-pip python3-setuptools python3-tk python3-wheel xz-utils file \
	make gcc gcc-multilib g++-multilib libsdl2-dev libmagic1

cmake_version=$(cmake --version | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
python_version=$(python3 --version | grep -oE "[0-9]+\.[0-9]+")
dtc_version=$(dtc --version | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")


if [[ $(echo -e "$cmake_version\n3.20.0" | sort -V | head -n1) = $CMAKE_MIN_VERSION ]]; then
	echo -e "${GREEN}The current cmake version is $cmake_version ${NC}"
else
	echo -e "${RED}Please update CMake version to at least 3.20.0${NC}"
	exit 1
fi

if [[ $(echo -e "$python_version\n3.8" | sort -V | head -n1) = $PYTHON_MIN_VERSION ]]; then
	echo -e "${GREEN}The current python version is $python_version ${NC}"
else
	echo -e "${RED}Please update Python version to at least 3.8 ${NC}"
	exit 1
fi

if [[ $(echo -e "$dtc_version\n1.4.6" | sort -V | head -n1) = $DTC_MIN_VERSION ]]; then
	echo -e "${GREEN}The current dtc version is $dtc_version ${NC}"
else
	echo -e "${RED}Please update DTC version to at least 1.4.6 ${NC}"
	exit 1
fi
echo -e "${GREEN}All versions OK${NC}"



sudo apt -y install python3-venv

source_venv source
#source "$zephyr_project_path/.venv/bin/activate"

pip install --upgrade pip
# install west using pip3
pip3 install west

# check if installation is successful
if [ $? -ne 0 ]; then
	echo "Failed to install west."
	exit 1
fi

echo "West is installed successfully."


west init $zephyr_project_path
cd $zephyr_project_path
west update
west zephyr-export
pip install -r ./zephyr/scripts/requirements.txt
# DEPRECATION是一个术语，用于指示某个软件包、工具或代码库中的某个功能、方法、
# 类或模块即将过时，可能会在未来的版本中被删除，而应该采用替代功能或方法。
# 在给出的示例中，DEPRECATION警告告诉用户正在使用的软件包中的一些组件是旧的，
# 未来版本可能会删除它们，并提供了一些替代选项。
# 警告中还提供了有关如何替换功能的指南和文档链接，
# 以便用户可以了解如何更新他们的代码。
pip install -r ./zephyr/scripts/requirements.txt
cd -



# get latest sdk version
latest_sdk=$(curl -s https://api.github.com/repos/zephyrproject-rtos/sdk-ng/releases/latest | grep tag_name | sed 's/[^0-9.]*\([0-9.]*\).*/\1/')

# set ZEPHYR_SDK_INSTALL_DIR
export ZEPHYR_SDK_INSTALL_DIR=$HOME/.local
zephyr_sdk_dir=$ZEPHYR_SDK_INSTALL_DIR/zephyr-sdk-${latest_sdk}

# check if SDK already exists in the specified directory
if [ -d "${zephyr_sdk_dir}" ]; then
	echo "Zephyr SDK already exists in the specified directory: $ZEPHYR_SDK_INSTALL_DIR"
	echo "Skipping installation"
else
	# download the SDK
	sdk_url="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${latest_sdk}/zephyr-sdk-${latest_sdk}_linux-x86_64.tar.gz"
	if [ ! -f "zephyr-sdk-${latest_sdk}_linux-x86_64.tar.gz" ]; then
		echo "Downloading Zephyr SDK version $latest_sdk from $sdk_url"
		wget $sdk_url
	else
		echo "Zephyr SDK already exists: zephyr-sdk-${latest_sdk}_linux-x86_64.tar.gz "
	fi

    # verify the download using sha256 checksums
    echo "Verifying download..."
    wget -q https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${latest_sdk}/sha256.sum
    sha256sum -c --ignore-missing sha256.sum || { echo "Error: SDK download checksum mismatch"; exit 1; }

    # extract the SDK
    echo "Extracting SDK..."
    tar -xzf zephyr-sdk-${latest_sdk}_linux-x86_64.tar.gz -C $ZEPHYR_SDK_INSTALL_DIR

    # clean up the archive and checksums
    rm zephyr-sdk-${latest_sdk}_linux-x86_64.tar.gz* sha256.sum*
    echo "Zephyr SDK version $latest_sdk has been installed to $ZEPHYR_SDK_INSTALL_DIR"
fi

cd ${zephyr_sdk_dir}
./setup.sh
cd -

echo -e "${GREEN}如需编译，请激活 Python 虚拟环境, 执行：source $zephyr_project_path/.venv/bin/activate${NC}"
echo -e "${GREEN}zephyr工程目录： $zephyr_project_path${NC}"
