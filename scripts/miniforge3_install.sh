#!/bin/bash
#SBATCH --job-name=miniforge3_install  # create a short name for your job
#SBATCH --output=%x.log         # job output file
#SBATCH --partition=pvc9        # cluster partition to be used
#SBATCH --nodes=1               # number of nodes
#SBATCH --gres=gpu:1            # number of allocated gpus per node
#SBATCH --time=00:30:00         # total run time limit (HH:MM:SS)

# Script that creates a new installation of the Miniforge3 flavour of conda,
# optionally creating a soft link to this installation.
# For information about miniforge, see:
# https://github.com/conda-forge/miniforge

# By default, this script installs to:
# ${HOME}/miniforge3
# and no soft link to this directory is created.

# Non-default installation directory and soft link can be set using
# the environment variables CONDA_INSTALL and CONDA_LINK, or using
# the command-line options: -i <install path> -l <link path>.
# If command-line options are used, these override the environment variables.

# Warning: any pre-existing files at the installation and link paths
# will be deleted.

# This script may be run interactively on a Dawn compute node
# (not on a login node):
# bash ./miniforge3_install.sh
# or it may be run on the Slurm batch system:
# sbatch --acount=<project account> ./miniforge3_install.sh

# Exit at first failure.
set -e

# Provide tilde expansion.
expand_path() {
    IN_PATH=$1
    if [[ "${IN_PATH:0:1}" == "~" ]] ; then
        for (( IDX=1; IDX<${#IN_PATH}; IDX++ )); do
            if [[ "/" == "${IN_PATH:$IDX:1}" ]]; then
                break
            fi
	done
	OUT_PATH=~${LOCAL_PATH:1:$((IDX-1))}${LOCAL_PATH:${IDX}}
    else
        OUT_PATH=${IN_PATH}
    fi
    echo ${OUT_PATH}
}

# Define default installation.
if [[ -z "${CONDA_ENV}" ]]; then
    CONDA_ENV="Miniforge3"
fi

if [[ -z "${CONDA_ENV_LC}" ]]; then
    CONDA_ENV_LC="$(echo ${CONDA_ENV} | tr [:upper:] [:lower:])"
fi

if [[ -z "${CONDA_HOME}" ]]; then
    CONDA_HOME=~/${CONDA_ENV_LC}
fi

if [[ -z "${CONDA_INSTALL}" ]]; then
    CONDA_INSTALL=${CONDA_HOME}
fi

if [[ -z "${CONDA_LINK}" ]]; then
    NO_LINK="true"
else
    NO_LINK="false"
fi

# Parse command-line options.
usage() {
    echo "usage: miniforge3_install [-h] [-i <install path>] [-l [<link path>]]"
    echo "    Install Miniforge3 flavour of conda."
    echo "Options:"
    echo "    -h: Print this help."
    echo "    -i: Install to <install path>;"
    echo "    -l: Link <install path> to <link path>."
    echo "If -i omitted, installation is to $CONDA_INSTALL."
    if [ -z "${CONDA_LINK}" ]; then
        echo "If -l omitted or <link path> unspecified, no link added."
    else
        echo "If -l omitted, installation linked to $CONDA_LINK."
    fi
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h)
            usage
	    exit 0
            ;;
        -i)
            if [[ -n "$2" && "$2" != -* ]]; then
                CONDA_INSTALL="$2"
		shift 2
            else
                echo "-i must be followed by install path"
                usage
		exit 1
            fi
            ;;
        -l)
            if [[ -n "$2" && "$2" != -* ]]; then
                CONDA_LINK="$2"
                NO_LINK="false"
                shift 2
            else
                NO_LINK="true"
                shift 1
            fi
            ;;
        -*)
            echo "Unknown option: $1"
            usage
	    exit 2
            ;;
    esac
done
if [[ "true" == "${NO_LINK}" ]]; then
    CONDA_LINK=""
    CONDA_LINK_ECHO="undefined"
else
    CONDA_LINK=$(echo "${CONDA_LINK//\'/~}" | sed "s|^~/|$HOME/|")
    mkdir -p ${CONDA_LINK}
    CONDA_LINK=$(realpath ${CONDA_LINK})
    CONDA_LINK_ECHO="${CONDA_LINK}"
fi
CONDA_INSTALL=$(echo "${CONDA_INSTALL//\'/~}" | sed "s|^~/|$HOME/|")
mkdir -p ${CONDA_INSTALL}
CONDA_INSTALL=$(realpath ${CONDA_INSTALL})

# Start timer.
T0=${SECONDS}
echo "Installation of ${CONDA_ENV} started on $(hostname): $(date)"
echo "Install path: ${CONDA_INSTALL}"
echo "Link path: ${CONDA_LINK_ECHO}"
echo ""

# Delete any pre-existing conda installation.
rm -rf "${CONDA_INSTALL}"
rm -rf "${CONDA_LINK}"

# Download and run the installation script.
INSTALL_SCRIPT="Miniforge3-$(uname)-$(uname -m).sh"
rm -rf "${INSTALL_SCRIPT}"
wget "https://github.com/conda-forge/miniforge/releases/latest/download/${INSTALL_SCRIPT}"
eval "bash ${INSTALL_SCRIPT} -b -p ${CONDA_INSTALL}"
rm -f "${INSTALL_SCRIPT}"

# Ensure that CONDA_LINK is path to conda installation.
if [ -n "${CONDA_LINK}" ]; then
    ln -s "${CONDA_INSTALL}" "${CONDA_LINK}"
    CONDA_LINK=$(realpath ${CONDA_LINK})
else
    CONDA_LINK=${CONDA_INSTALL}
fi

# Update to latest conda version.
source ${CONDA_LINK}/bin/activate
conda update -n base -c conda-forge conda -y

# Report installation time.
echo ""
echo "Installation of miniforge3 completed: $(date)"
echo "Installation time: $((${SECONDS}-${T0})) seconds"

echo ""
echo "Set up environment for ${CONDA_ENV} with:"
echo "source ${CONDA_LINK}/bin/activate"
