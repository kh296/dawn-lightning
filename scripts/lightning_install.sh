#!/bin/bash
#SBATCH --job-name=lightning_install  # create a name for your job
#SBATCH --output=%x.log              # job output file
#SBATCH --partition=pvc9             # cluster partition to be used
#SBATCH --nodes=1                    # number of nodes
#SBATCH --gres=gpu:1                 # number of allocated gpus per node
#SBATCH --time=01:30:00              # total run time limit (HH:MM:SS)

# Script for installing Lightning on the Dawn supercomputer.
#
# This installation relies on the user having a conda installation
# at ${CONDA_HOME}.  If CONDA_HOME is null but CONDA_PREFIX is non-null,
# the former is set to be equal to the latter.  If both CONDA_HOME and
# CONDA_PREFIX are null, CONDA_HOME is set to ${HOME}/miniforge3.  In this
# case, if conda isn't available at ${HOME}/miniforge3 then
# the Miniforge3 flavour of conda will be installed by running
# ./miniforge3_install.sh with default settings.
# For information about the Miniforge3 flavour
# of conda, see: https://conda-forge.org/download/
# For information about ./miniforge3_install.sh, use:
# ./miniforge3_install.sh -h
#
# After installation, if the environment variable CONDA_ENV wasn't set,
# the environment for using Lightning can be activated by sourcing the file
# lightning-setup.sh, created in the directory ../envs relative to where
# the current script is run.  Otherwise, the file to source is
# ../envs/${CONDA_ENV}-setup.sh
#
# On Dawn, the current script may be run interactively on a compute node
# (not on a login node):
# bash ./lightning_install.sh
# or it may be submitted from a login node to the Slurm batch system:
# sbatch --account=<project account> ./lightning_install.sh

# Exit at first failure.
set -e

PROJECT_NAME="Lightning"
PROJECT_NAME_LC="$(echo ${PROJECT_NAME} | tr [:upper:] [:lower:])"

# Parse command-line options.
usage() {
    echo "usage: lightning_install.sh [-h] [-c <conda home>] [-e <conda env>]"
    echo "    Install Lightning in a conda environment."
    echo "Options:"
    echo "    -h: Print this help."
    echo "    -c: Use conda installation at <conda home>."
    echo "    -e: Create, and install to, conda environment <conda env>."
    echo "If -c omitted, path to conda installation is first non-empty string from:"
    echo "    \"\${CONDA_HOME}\", \"\${CONDA_PREFIX}\", \"\${HOME}/miniforge3\""
    echo "    If last of these is selected, conda will be installed here"
    echo "    if not already present."
    echo "If -e omitted, the name for the conda environment defaults to \"${PROJECT_NAME_LC}\"."
    echo "Any pre-existing conda environment <conda env> (specified with -e)"
    echo "    or \"${PROJECT_NAME_LC}\" (-e omitted) will be removed."
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h)
            usage
	    exit 0
            ;;
        -c)
            if [[ -n "$2" && "$2" != -* ]]; then
                CONDA_HOME="$2"
		shift 2
            else
                echo "-c must be followed by path to conda installation"
                usage
		exit 1
            fi
            ;;
        -e)
            if [[ -n "$2" && "$2" != -* ]]; then
                CONDA_ENV="$2"
                shift 2
            else
                echo "-e must be followed by name of conda environment"
                exit 1
            fi
            ;;
        -*)
            echo "Unknown option: $1"
            usage
	    exit 1
            ;;
    esac
done

if [[ -z "${CONDA_ENV}" ]]; then
    CONDA_ENV=${PROJECT_NAME_LC}
fi

# Determine system being used.
if [[ "$(hostname)" == "pvc-s"* ]]; then
    SYSTEM="Dawn"
elif [[ "$(hostname)" == "gpu-u"* ]]; then
    SYSTEM="Zenith"
elif [[ "$(hostname)" == *"-pl1"* ]]; then
    SYSTEM="aac6"
elif [[ "${OSTYPE}" == "darwin"* ]]; then
    SYSTEM="macOS"
else
    echo "Installation of ${PROJECT_NAME} for ${OSTYPE} on $(hostname) not handled"
    echo "Exiting: $(date)"
    exit
fi

# Check that conda is available.
if [ -z "${CONDA_HOME}" ]; then
    if [ -z "${CONDA_PREFIX}" ]; then
        CONDA_HOME="${HOME}/miniforge3"
        if ! [ -d "${CONDA_HOME}" ]; then
            ./miniforge3_install.sh
        fi
    else
        CONDA_HOME="${CONDA_PREFIX}"
    fi
fi

# Expand path, without following symbolic links.
CONDA_HOME="${CONDA_HOME/#\~/${HOME}}"
CONDA_HOME=$(cd "$(dirname "${CONDA_HOME}")" && pwd -P)/$(basename "${CONDA_HOME}")

if ! [ -d "${CONDA_HOME}" ]; then
    echo "Conda installation not found at ${CONDA_HOME}"
    echo "Exiting: $(date)"
    exit 2
fi

# Perform installation.
echo "Installation of ${PROJECT_NAME} for ${OSTYPE} on $(hostname) started: $(date)"
T0=${SECONDS}

# Create script for environment setup.
ENVS_DIR=$(realpath ..)/envs
mkdir -p ${ENVS_DIR}
SETUP="${ENVS_DIR}/${CONDA_ENV}-setup.sh"
DAWN_SETUP="/dev/null"
ZENITH_SETUP="/dev/null"
AAC6_SETUP="/dev/null"
MACOS_SETUP="/dev/null"
if [[ "Dawn" == "${SYSTEM}" ]]; then
    DAWN_SETUP="${SETUP}"
elif [[ "Zenith" == "${SYSTEM}" ]]; then
    ZENITH_SETUP="${SETUP}"
elif [[ "aac6" == "${SYSTEM}" ]]; then
    AAC6_SETUP="${SETUP}"
elif [[ "macOS" == "${SYSTEM}" ]]; then
    MACOS_SETUP="${SETUP}"
fi

rm -rf ${SETUP}
cat <<EOF >${SETUP}
# Setup script for ${CONDA_ENV} on ${SYSTEM}.
# Generated on $(hostname), $(date +"%Y-%m-%d (%a) %H:%M:%S %Z").

EOF

cat <<EOF >>${DAWN_SETUP}
# Load modules.
module purge
module load rhel9/default-dawn
source /usr/local/dawn/software/external/intel-oneapi/2026.0.0/setvars.sh

# Set level-zero environment variables:
# https://oneapi-src.github.io/level-zero-spec/level-zero/latest/core/PROG.html#environment-variables
#

# Define device hierarchy model and affinity mask.
# See: https://www.intel.com/content/www/us/en/developer/articles/technical/flattening-gpu-tile-hierarchy.html
# Define whether a GPU is treated as a single root device ("COMPOSITE")
# or as a root device per stack ("FLAT").
if [[ -z "\${ZE_FLAT_DEVICE_HIERARCHY}" ]]; then
    export ZE_FLAT_DEVICE_HIERARCHY="FLAT"
fi
if [[ "COMPOSITE" == "\${ZE_FLAT_DEVICE_HIERARCHY}" ]]; then
    DEVICES_PER_GPU=1
else
    DEVICES_PER_GPU=2
fi
# Determine number of tasks per node, with one task per GPU root device,
# or defaulting to 1 if there are no GPUs.
# Where GPUs are present, set affinity mask to match number of root devices.
if [[ -z "\${SLURM_GPUS_ON_NODE}" ]]; then
    export SLURM_NTASKS_PER_NODE=1
else
    export SLURM_NTASKS_PER_NODE=\$((\${SLURM_GPUS_ON_NODE}*\${DEVICES_PER_GPU}))
    if [[ \${SLURM_NTASKS_PER_NODE} -gt 1 ]]; then
        export ZE_AFFINITY_MASK=\$(seq -s, 0 \$((\${SLURM_NTASKS_PER_NODE}-1)))
    else
        export ZE_AFFINITY_MASK=0
    fi
fi

#
# Set some variables relevant to Intel MPI Library:
# https://www.intel.com/content/www/us/en/docs/mpi-library/developer-reference-linux/2021-15/environment-variable-reference.html
#

# Set variables relating to GPU support.
# See: https://www.intel.com/content/www/us/en/docs/mpi-library/developer-reference-linux/2021-15/gpu-support.html
# Disable/enable GPU support (default: 0).
export I_MPI_OFFLOAD=1
# Disable/enable GPU pinning (default: 0).
export I_MPI_OFFLOAD_PIN=1
# Enable/disable assumption that all buffers in an operation have the same type
# (default: 0).
export I_MPI_OFFLOAD_SYMMETRIC=0

# Set hydra environment variables.
# See: https://www.intel.com/content/www/us/en/docs/mpi-library/developer-reference-linux/2021-15/hydra-environment-variables.html
# Disable/enable process placement provided by job scheduler (default:1)
export I_MPI_JOB_RESPECT_PROCESS_PLACEMENT=0
# Set bootstrap server (default:"ssh")
export I_MPI_HYDRA_BOOTSTRAP="slurm"

# Configure debug output.
# See: https://www.intel.com/content/www/us/en/docs/mpi-library/developer-reference-linux/2021-15/other-environment-variables.html
# See: https://www.intel.com/content/www/us/en/docs/oneapi/optimization-guide-gpu/2024-0/intel-mpi-for-gpu-clusters.html
export I_MPI_DEBUG=0

#
# Set some variables relevant to OneAPI collective communications library
# (oneCCL):
# https://uxlfoundation.github.io/oneCCL/env-variables.html#ccl-ze-ipc-exchange
#

# Select transport for inter-process communication (default: "mpi").
# See: https://uxlfoundation.github.io/oneCCL/env-variables.html#ccl-atl-transport
export CCL_ATL_TRANSPORT="ofi"

# Set CCL log level (default: "warn").
# See: https://uxlfoundation.github.io/oneCCL/env-variables.html#ccl-log-level
export CCL_LOG_LEVEL="warn"

# Set CCL process launcher (default: "hydra).
# See: https://uxlfoundation.github.io/oneCCL/env-variables.html#ccl-process-launcher
export CCL_PROCESS_LAUNCHER="hydra"

# Set mechanism for CCL level zero inter-process communications
# (default: pidfd).
# See: https://uxlfoundation.github.io/oneCCL/env-variables.html#ccl-ze-ipc-exchange
export CCL_ZE_IPC_EXCHANGE=sockets

# Define filters for selection multiple network interfaces cards (NICs).
# See:
# https://uxlfoundation.github.io/oneCCL/env-variables.html#multi-nic
#
# Control multi-NIC selection by NIC locality.
# See: https://uxlfoundation.github.io/oneCCL/env-variables.html#ccl-ze-ipc-exchange
# export CCL_MNIC="none"
#
# Control multi-NIC selection by NIC names.
# See: https://uxlfoundation.github.io/oneCCL/env-variables.html#ccl-mnic-name
#export CCL_MNIC_NAME=
#
# Specify the maximum number of NICs to be selected.
# https://uxlfoundation.github.io/oneCCL/env-variables.html#ccl-mnic-count
#export CCL_MNIC_COUNT=
EOF

cat <<EOF >>${MACOS_SETUP}
# Initialise environment variables that may be used at run time.
# Define network interface.
export GLOO_SOCKET_IFNAME="en0"
EOF

cat <<EOF >>${ZENITH_SETUP}
# Load modules.
module purge
module load rhel9/mi355x/base
module load openmpi

EOF

cat <<EOF >>${AAC6_SETUP}
# Load modules.
module purge
module load rocm
module load openmpi

# Set network interface for communication:
# https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html#nccl-socket-ifname
# Possibilities for listing network interfaces include:
# Linux: ip addr, netstat -i, ifconfig
# MacOS: networksetup -listallhardwarereports, netstat -i, ifconfig
export NCCL_SOCKET_IFNAME="enp129s0"
EOF

cat <<EOF >>${SETUP}

# Initialise conda.
source ${CONDA_HOME}/bin/activate

# Activate environment.
EOF

# Set up installation environment.
source ${SETUP}
conda update -n base -c conda-forge conda -y

# Delete any pre-existing environment.
if [ -d "${CONDA_HOME}/envs/${CONDA_ENV}" ]; then
    rm -rf ${CONDA_HOME}/envs/${CONDA_ENV}
fi

# Create and activate the environment.
CMD="conda create -n ${CONDA_ENV} -y python=3.12 'setuptools>=77.0.3,<81.0.0'"
echo "${CMD}"
eval "${CMD}"
CMD="conda activate ${CONDA_ENV}"
echo "${CMD}" >> "${SETUP}"
eval "${CMD}"

# Clone lightning-xpu project.
PROJECTS_DIR=$(realpath ..)/projects
LIGHTNING_XPU="${PROJECTS_DIR}/lightning-xpu"
if [[ ! -d "${LIGHTNING_XPU}" ]]; then
    CMD="git clone https://github.com/kh296/lightning-xpu ${LIGHTNING_XPU}"
    echo "Cloning lightning-xpu"
    echo "${CMD}"
    eval "${CMD}"
fi
if [[ ! -d "${LIGHTNING_XPU}/envs" ]]; then
    mkdir ${LIGHTNING_XPU}/envs
    cp ${SETUP} ${LIGHTNING_XPU}/envs 
    echo ""
fi

# Install additional packages.
echo "Installing packages:"
OPTS=""
TORCH="torch torchvision"
if [[ "Dawn" == "${SYSTEM}" ]]; then
    OPTS=" --index-url https://download.pytorch.org/whl/xpu"
elif [[ "aac6" == "${SYSTEM}" ]]; then
    OPTS=" --index-url https://download.pytorch.org/whl/rocm7.2"
elif [[ "Zenith" == "${SYSTEM}" ]]; then
    OPTS=" --index-url https://repo.amd.com/rocm/whl-multi-arch/"
    TORCH="torch[device-gfx950]==2.12.0+rocm7.14.0\
 torchvision[device-gfx950]==0.27.0+rocm7.14.0"
fi
CMDS=(
    "python -m pip install --upgrade pip"
    "python -m pip install uv"
    "uv pip install${OPTS} ${TORCH}"
    "uv pip install lightning[extra] litmodels"
)
if [[ "Dawn" == "${SYSTEM}" ]]; then
    CMDS+=("uv pip install ${LIGHTNING_XPU}")
    #CMDS+=("uv pip install git+https://github.com/kh296/lightning-xpu#egg=lightning_xpu")
fi

for CMD in "${CMDS[@]}"; do
    echo ""
    echo "${CMD}"
    ${CMD}
done

T1=${SECONDS}

# Check imports.
echo ""
echo "Performing initial imports:"
CMD="python -c 'import lightning'"
echo "${CMD}"
eval "${CMD}"

# Check devices.
echo ""
echo "Checking devices:"
python - <<EOF
"""
Python code for checking devices seen by lightning.
"""
import socket
try:
    import lightning_xpu
except ModuleNotFoundError:
    pass
from lightning.pytorch.accelerators import AcceleratorRegistry
from lightning.fabric.utilities.exceptions import MisconfigurationException

print(f"\nDevices seen by lightning on {socket.gethostname()}:")
device_types = sorted(AcceleratorRegistry.available_accelerators())
len_device_field = max(len(device_type) for device_type in device_types)

for device_type in device_types:
    try:
        device = AcceleratorRegistry.get(device_type)
    except ModuleNotFoundError:
        device = None
    n_device = 0
    devices = []
    if device is not None:
        n_device = device.auto_device_count()
        try:
            devices = device.get_parallel_devices(n_device)
        except MisconfigurationException:
            n_device = 0
        except TypeError:
            devices = device.get_parallel_devices(list(range(n_device)))

    print(f"{device_type:<{len_device_field}} : {n_device}")
    for device in devices:
        print(f"    {device}")
EOF
T2=${SECONDS}

echo ""
echo "Installation of ${PROJECT_NAME} for ${OSTYPE} on $(hostname) completed: $(date)"
echo "Time for installation: $((${T1}-${T0})) seconds"
echo "Time for installation checks: $((${T2}-${T1})) seconds"

echo ""
echo "Set up environment for ${PROJECT_NAME} with:"
echo "source ${SETUP}"
