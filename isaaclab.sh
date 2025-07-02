#!/usr/bin/env bash

# Copyright (c) 2022-2025, The Isaac Lab Project Developers (https://github.com/isaac-sim/IsaacLab/blob/main/CONTRIBUTORS.md).
# All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause

#==
# Configurations
#==

# Exits if error occurs
set -e

# Set tab-spaces
tabs 4

# get source directory
export ISAACLAB_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

#==
# Helper functions
#==

# check if running in docker
is_docker() {
    [ -f /.dockerenv ] || \
    grep -q docker /proc/1/cgroup || \
    [[ $(cat /proc/1/comm) == "containerd-shim" ]] || \
    grep -q docker /proc/mounts || \
    [[ "$(hostname)" == *"."* ]]
}

# extract isaac sim path
extract_isaacsim_path() {
    # Use the sym-link path to Isaac Sim directory
    local isaac_path=${ISAACLAB_PATH}/_isaac_sim
    # If above path is not available, try to find the path using python
    if [ ! -d "${isaac_path}" ]; then
        # Use the python executable to get the path
        local python_exe=$(extract_python_exe)
        # Retrieve the path importing isaac sim and getting the environment path
        if [ $(${python_exe} -m pip list | grep -c 'isaacsim-rl') -gt 0 ]; then
            local isaac_path=$(${python_exe} -c "import isaacsim; import os; print(os.environ['ISAAC_PATH'])")
        fi
    fi
    # check if there is a path available
    if [ ! -d "${isaac_path}" ]; then
        # throw an error if no path is found
        echo -e "[ERROR] Unable to find the Isaac Sim directory: '${isaac_path}'" >&2
        echo -e "\tThis could be due to the following reasons:" >&2
        echo -e "\t1. Conda environment is not activated." >&2
        echo -e "\t2. Isaac Sim pip package 'isaacsim-rl' is not installed." >&2
        echo -e "\t3. Isaac Sim directory is not available at the default path: ${ISAACLAB_PATH}/_isaac_sim" >&2
        # exit the script
        exit 1
    fi
    # return the result
    echo ${isaac_path}
}

# extract the python from isaacsim
extract_python_exe() {
    # check if using virtual environment (venv or conda)
    if ! [[ -z "${VIRTUAL_ENV}" ]]; then
        # use venv python
        local python_exe=${VIRTUAL_ENV}/bin/python
    elif ! [[ -z "${CONDA_PREFIX}" ]]; then
        # use conda python
        local python_exe=${CONDA_PREFIX}/bin/python
    else
        # use kit python
        local python_exe=${ISAACLAB_PATH}/_isaac_sim/python.sh

    if [ ! -f "${python_exe}" ]; then
            # note: we need to check system python for cases such as docker
            # inside docker, if user installed into system python, we need to use that
            # otherwise, use the python from the kit
            if [ $(python -m pip list | grep -c 'isaacsim-rl') -gt 0 ]; then
                local python_exe=$(which python)
            fi
        fi
    fi
    # check if there is a python path available
    if [ ! -f "${python_exe}" ]; then
        echo -e "[ERROR] Unable to find any Python executable at path: '${python_exe}'" >&2
        echo -e "\tThis could be due to the following reasons:" >&2
        echo -e "\t1. Virtual environment (venv) or Conda environment is not activated." >&2
        echo -e "\t2. Isaac Sim pip package 'isaacsim-rl' is not installed." >&2
        echo -e "\t3. Python executable is not available at the default path: ${ISAACLAB_PATH}/_isaac_sim/python.sh" >&2
        exit 1
    fi
    # return the result
    echo ${python_exe}
}

# extract the simulator exe from isaacsim
extract_isaacsim_exe() {
    # obtain the isaac sim path
    local isaac_path=$(extract_isaacsim_path)
    # isaac sim executable to use
    local isaacsim_exe=${isaac_path}/isaac-sim.sh
    # check if there is a python path available
    if [ ! -f "${isaacsim_exe}" ]; then
        # check for installation using Isaac Sim pip
        # note: pip installed Isaac Sim can only come from a direct
        # python environment, so we can directly use 'python' here
        if [ $(python -m pip list | grep -c 'isaacsim-rl') -gt 0 ]; then
            # Isaac Sim - Python packages entry point
            local isaacsim_exe="isaacsim isaacsim.exp.full"
        else
            echo "[ERROR] No Isaac Sim executable found at path: ${isaac_path}" >&2
            exit 1
        fi
    fi
    # return the result
    echo ${isaacsim_exe}
}

# check if input directory is a python extension and install the module
install_isaaclab_extension() {
    # retrieve the python executable
    python_exe=$(extract_python_exe)
    # if the directory contains setup.py then install the python module
    if [ -f "$1/setup.py" ]; then
        echo -e "\t module: $1"
        # check if uv is available, otherwise fallback to pip
        if command -v uv &> /dev/null; then
            uv pip install --editable $1
        else
            ${python_exe} -m pip install --editable $1
        fi
    fi
}

# setup virtual environment for Isaac Lab using uv or venv
setup_venv() {
    # get environment name/path from input
    local env_name=$1
    local venv_path="${ISAACLAB_PATH}/${env_name}"
    
    # check if uv is available, otherwise use venv
    if command -v uv &> /dev/null; then
        echo "[INFO] Using uv to create virtual environment..."
        # check if the environment exists
        if [ -d "${venv_path}" ]; then
            echo -e "[INFO] Virtual environment '${env_name}' already exists at ${venv_path}."
        else
            echo -e "[INFO] Creating virtual environment '${env_name}' using uv..."
            uv venv ${venv_path}
        fi
        
        # activate the environment and install dependencies
        source ${venv_path}/bin/activate
        
        # install dependencies using uv
        if [ -f "${ISAACLAB_PATH}/pyproject.toml" ]; then
            echo -e "[INFO] Installing dependencies from pyproject.toml..."
            uv pip install -e .
        elif [ -f "${ISAACLAB_PATH}/requirements.txt" ]; then
            echo -e "[INFO] Installing dependencies from requirements.txt..."
            uv pip install -r ${ISAACLAB_PATH}/requirements.txt
        fi
        
    else
        echo "[INFO] Using python venv to create virtual environment..."
        # check python is available
        if ! command -v python &> /dev/null; then
            echo "[ERROR] Python could not be found. Please install python and try again."
            exit 1
        fi
        
        # check if the environment exists
        if [ -d "${venv_path}" ]; then
            echo -e "[INFO] Virtual environment '${env_name}' already exists at ${venv_path}."
        else
            echo -e "[INFO] Creating virtual environment '${env_name}' using python venv..."
            python -m venv ${venv_path}
        fi
        
        # activate the environment and install dependencies
        source ${venv_path}/bin/activate
        
        # upgrade pip first
        python -m pip install --upgrade pip
        
        # install dependencies
        if [ -f "${ISAACLAB_PATH}/pyproject.toml" ]; then
            echo -e "[INFO] Installing dependencies from pyproject.toml..."
            python -m pip install -e .
        elif [ -f "${ISAACLAB_PATH}/requirements.txt" ]; then
            echo -e "[INFO] Installing dependencies from requirements.txt..."
            python -m pip install -r ${ISAACLAB_PATH}/requirements.txt
        fi
    fi

    # create activation script
    local activate_script="${venv_path}/bin/activate_isaaclab"
    printf '%s\n' '#!/usr/bin/env bash' '' \
        '# Activate Isaac Lab virtual environment' \
        'source '${venv_path}'/bin/activate' \
        '' \
        '# Set Isaac Lab environment variables' \
        'export ISAACLAB_PATH='${ISAACLAB_PATH}'' \
        'alias isaaclab='${ISAACLAB_PATH}'/isaaclab.sh' \
        '' \
        '# show icon if not running headless' \
        'export RESOURCE_NAME="IsaacSim"' \
        '' > ${activate_script}

    # check if we have _isaac_sim directory -> if so that means binaries were installed.
    local isaacsim_setup_env_script=${ISAACLAB_PATH}/_isaac_sim/setup_conda_env.sh
    if [ -f "${isaacsim_setup_env_script}" ]; then
        printf '%s\n' \
            '# for Isaac Sim' \
            'source '${isaacsim_setup_env_script}'' \
            '' >> ${activate_script}
    fi

    # make the script executable
    chmod +x ${activate_script}
    
    # deactivate the environment
    deactivate
    
    # add information to the user
    echo -e "[INFO] Created virtual environment '${env_name}' at ${venv_path}.\n"
    echo -e "\t\t1. To activate the environment, run:                source ${activate_script}"
    echo -e "\t\t   Or manually:                                     source ${venv_path}/bin/activate"
    echo -e "\t\t2. To install Isaac Lab extensions, run:            isaaclab -i"
    echo -e "\t\t3. To perform formatting, run:                      isaaclab -f"
    echo -e "\t\t4. To deactivate the environment, run:              deactivate"
    echo -e "\n"
}

# setup anaconda environment for Isaac Lab (kept for backward compatibility)
setup_conda_env() {
    # get environment name from input
    local env_name=$1
    # check conda is installed
    if ! command -v conda &> /dev/null
    then
        echo "[ERROR] Conda could not be found. Please install conda and try again."
        exit 1
    fi

    # check if the environment exists
    if { conda env list | grep -w ${env_name}; } >/dev/null 2>&1; then
        echo -e "[INFO] Conda environment named '${env_name}' already exists."
    else
        echo -e "[INFO] Creating conda environment named '${env_name}'..."
        echo -e "[INFO] Installing dependencies from ${ISAACLAB_PATH}/environment.yml"

        # Create environment from YAML file with specified name
        conda env create -y --file ${ISAACLAB_PATH}/environment.yml -n ${env_name}
    fi

    # cache current paths for later
    cache_pythonpath=$PYTHONPATH
    cache_ld_library_path=$LD_LIBRARY_PATH
    # clear any existing files
    rm -f ${CONDA_PREFIX}/etc/conda/activate.d/setenv.sh
    rm -f ${CONDA_PREFIX}/etc/conda/deactivate.d/unsetenv.sh
    # activate the environment
    source $(conda info --base)/etc/profile.d/conda.sh
    conda activate ${env_name}
    # setup directories to load Isaac Sim variables
    mkdir -p ${CONDA_PREFIX}/etc/conda/activate.d
    mkdir -p ${CONDA_PREFIX}/etc/conda/deactivate.d

    # add variables to environment during activation
    printf '%s\n' '#!/usr/bin/env bash' '' \
        '# for Isaac Lab' \
        'export ISAACLAB_PATH='${ISAACLAB_PATH}'' \
        'alias isaaclab='${ISAACLAB_PATH}'/isaaclab.sh' \
        '' \
        '# show icon if not runninng headless' \
        'export RESOURCE_NAME="IsaacSim"' \
        '' > ${CONDA_PREFIX}/etc/conda/activate.d/setenv.sh

    # check if we have _isaac_sim directory -> if so that means binaries were installed.
    # we need to setup conda variables to load the binaries
    local isaacsim_setup_conda_env_script=${ISAACLAB_PATH}/_isaac_sim/setup_conda_env.sh

    if [ -f "${isaacsim_setup_conda_env_script}" ]; then
        # add variables to environment during activation
        printf '%s\n' \
            '# for Isaac Sim' \
            'source '${isaacsim_setup_conda_env_script}'' \
            '' >> ${CONDA_PREFIX}/etc/conda/activate.d/setenv.sh
    fi

    # reactivate the environment to load the variables
    # needed because deactivate complains about Isaac Lab alias since it otherwise doesn't exist
    conda activate ${env_name}

    # remove variables from environment during deactivation
    printf '%s\n' '#!/usr/bin/env bash' '' \
        '# for Isaac Lab' \
        'unalias isaaclab &>/dev/null' \
        'unset ISAACLAB_PATH' \
        '' \
        '# restore paths' \
        'export PYTHONPATH='${cache_pythonpath}'' \
        'export LD_LIBRARY_PATH='${cache_ld_library_path}'' \
        '' \
        '# for Isaac Sim' \
        'unset RESOURCE_NAME' \
        '' > ${CONDA_PREFIX}/etc/conda/deactivate.d/unsetenv.sh

    # check if we have _isaac_sim directory -> if so that means binaries were installed.
    if [ -f "${isaacsim_setup_conda_env_script}" ]; then
        # add variables to environment during activation
        printf '%s\n' \
            '# for Isaac Sim' \
            'unset CARB_APP_PATH' \
            'unset EXP_PATH' \
            'unset ISAAC_PATH' \
            '' >> ${CONDA_PREFIX}/etc/conda/deactivate.d/unsetenv.sh
    fi

    # deactivate the environment
    conda deactivate
    # add information to the user about alias
    echo -e "[INFO] Added 'isaaclab' alias to conda environment for 'isaaclab.sh' script."
    echo -e "[INFO] Created conda environment named '${env_name}'.\n"
    echo -e "\t\t1. To activate the environment, run:                conda activate ${env_name}"
    echo -e "\t\t2. To install Isaac Lab extensions, run:            isaaclab -i"
    echo -e "\t\t4. To perform formatting, run:                      isaaclab -f"
    echo -e "\t\t5. To deactivate the environment, run:              conda deactivate"
    echo -e "\n"
}

# update the vscode settings from template and isaac sim settings
update_vscode_settings() {
    echo "[INFO] Setting up vscode settings..."
    # retrieve the python executable
    python_exe=$(extract_python_exe)
    # path to setup_vscode.py
    setup_vscode_script="${ISAACLAB_PATH}/.vscode/tools/setup_vscode.py"
    # check if the file exists before attempting to run it
    if [ -f "${setup_vscode_script}" ]; then
        ${python_exe} "${setup_vscode_script}"
    else
        echo "[WARNING] Unable to find the script 'setup_vscode.py'. Aborting vscode settings setup."
    fi
}

# print the usage description
print_help () {
    echo -e "\nusage: $(basename "$0") [-h] [-i] [-f] [-p] [-s] [-t] [-o] [-v] [-d] [-n] [-c] [-e] -- Utility to manage Isaac Lab."
    echo -e "\noptional arguments:"
    echo -e "\t-h, --help           Display the help content."
    echo -e "\t-i, --install [LIB]  Install the extensions inside Isaac Lab and learning frameworks as extra dependencies. Default is 'all'."
    echo -e "\t-f, --format         Run pre-commit to format the code and check lints."
    echo -e "\t-p, --python         Run the python executable provided by Isaac Sim or virtual environment (if active)."
    echo -e "\t-s, --sim            Run the simulator executable (isaac-sim.sh) provided by Isaac Sim."
    echo -e "\t-t, --test           Run all python pytest tests."
    echo -e "\t-o, --docker         Run the docker container helper script (docker/container.sh)."
    echo -e "\t-v, --vscode         Generate the VSCode settings file from template."
    echo -e "\t-d, --docs           Build the documentation from source using sphinx."
    echo -e "\t-n, --new            Create a new external project or internal task from template."
    echo -e "\t-c, --conda [NAME]   Create the conda environment for Isaac Lab. Default name is 'env_isaaclab'."
    echo -e "\t-e, --venv [NAME]    Create the virtual environment for Isaac Lab using uv or venv. Default name is 'venv_isaaclab'."
    echo -e "\n" >&2
}


#==
# Main
#==

# check argument provided
if [ -z "$*" ]; then
    echo "[Error] No arguments provided." >&2;
    print_help
    exit 1
fi

# pass the arguments
while [[ $# -gt 0 ]]; do
    # read the key
    case "$1" in
        -i|--install)
            # install the python packages in IsaacLab/source directory
            echo "[INFO] Installing extensions inside the Isaac Lab repository..."
            python_exe=$(extract_python_exe)
            # recursively look into directories and install them
            # this does not check dependencies between extensions
            export -f extract_python_exe
            export -f install_isaaclab_extension
            # source directory
            find -L "${ISAACLAB_PATH}/source" -mindepth 1 -maxdepth 1 -type d -exec bash -c 'install_isaaclab_extension "{}"' \;
            # install the python packages for supported reinforcement learning frameworks
            echo "[INFO] Installing extra requirements such as learning frameworks..."
            # check if specified which rl-framework to install
            if [ -z "$2" ]; then
                echo "[INFO] Installing all rl-frameworks..."
                framework_name="all"
            elif [ "$2" = "none" ]; then
                echo "[INFO] No rl-framework will be installed."
                framework_name="none"
                shift # past argument
            else
                echo "[INFO] Installing rl-framework: $2"
                framework_name=$2
                shift # past argument
            fi
            # install the learning frameworks specified
            if command -v uv &> /dev/null; then
                uv pip install -e ${ISAACLAB_PATH}/source/isaaclab_rl["${framework_name}"]
                uv pip install -e ${ISAACLAB_PATH}/source/isaaclab_mimic["${framework_name}"]
            else
                ${python_exe} -m pip install -e ${ISAACLAB_PATH}/source/isaaclab_rl["${framework_name}"]
                ${python_exe} -m pip install -e ${ISAACLAB_PATH}/source/isaaclab_mimic["${framework_name}"]
            fi

            # check if we are inside a docker container or are building a docker image
            # in that case don't setup VSCode since it asks for EULA agreement which triggers user interaction
            if is_docker; then
                echo "[INFO] Running inside a docker container. Skipping VSCode settings setup."
                echo "[INFO] To setup VSCode settings, run 'isaaclab -v'."
            else
                # update the vscode settings
                update_vscode_settings
            fi

            # unset local variables
            unset extract_python_exe
            unset install_isaaclab_extension
            shift # past argument
            ;;
        -c|--conda)
            # use default name if not provided
            if [ -z "$2" ]; then
                echo "[INFO] Using default conda environment name: env_isaaclab"
                conda_env_name="env_isaaclab"
            else
                echo "[INFO] Using conda environment name: $2"
                conda_env_name=$2
                shift # past argument
            fi
            # setup the conda environment for Isaac Lab
            setup_conda_env ${conda_env_name}
            shift # past argument
            ;;
        -e|--venv)
            # use default name if not provided
            if [ -z "$2" ]; then
                echo "[INFO] Using default virtual environment name: venv_isaaclab"
                venv_name="venv_isaaclab"
            else
                echo "[INFO] Using virtual environment name: $2"
                venv_name=$2
                shift # past argument
            fi
            # setup the virtual environment for Isaac Lab
            setup_venv ${venv_name}
            shift # past argument
            ;;
        -f|--format)
            # reset the python path to avoid conflicts with pre-commit
            # this is needed because the pre-commit hooks are installed in a separate virtual environment
            # and it uses the system python to run the hooks
            if [ -n "${CONDA_DEFAULT_ENV}" ]; then
                cache_pythonpath=${PYTHONPATH}
                export PYTHONPATH=""
            fi
            # run the formatter over the repository
            # check if pre-commit is installed
            if ! command -v pre-commit &>/dev/null; then
                echo "[INFO] Installing pre-commit..."
                if command -v uv &> /dev/null; then
                    uv pip install pre-commit
                else
                    pip install pre-commit
                fi
            fi
            # always execute inside the Isaac Lab directory
            echo "[INFO] Formatting the repository..."
            cd ${ISAACLAB_PATH}
            pre-commit run --all-files
            cd - > /dev/null
            # set the python path back to the original value
            if [ -n "${CONDA_DEFAULT_ENV}" ]; then
                export PYTHONPATH=${cache_pythonpath}
            fi
            shift # past argument
            # exit neatly
            break
            ;;
        -p|--python)
            # run the python provided by isaacsim
            python_exe=$(extract_python_exe)
            echo "[INFO] Using python from: ${python_exe}"
            shift # past argument
            ${python_exe} "$@"
            # exit neatly
            break
            ;;
        -s|--sim)
            # run the simulator exe provided by isaacsim
            isaacsim_exe=$(extract_isaacsim_exe)
            echo "[INFO] Running isaac-sim from: ${isaacsim_exe}"
            shift # past argument
            ${isaacsim_exe} --ext-folder ${ISAACLAB_PATH}/source $@
            # exit neatly
            break
            ;;
        -n|--new)
            # run the template generator script
            python_exe=$(extract_python_exe)
            shift # past argument
            echo "[INFO] Installing template dependencies..."
            if command -v uv &> /dev/null; then
                uv pip install -q -r ${ISAACLAB_PATH}/tools/template/requirements.txt
            else
                ${python_exe} -m pip install -q -r ${ISAACLAB_PATH}/tools/template/requirements.txt
            fi
            echo -e "\n[INFO] Running template generator...\n"
            ${python_exe} ${ISAACLAB_PATH}/tools/template/cli.py $@
            # exit neatly
            break
            ;;
        -t|--test)
            # run the python provided by isaacsim
            python_exe=$(extract_python_exe)
            shift # past argument
            ${python_exe} -m pytest ${ISAACLAB_PATH}/tools $@
            # exit neatly
            break
            ;;
        -o|--docker)
            # run the docker container helper script
            docker_script=${ISAACLAB_PATH}/docker/container.sh
            echo "[INFO] Running docker utility script from: ${docker_script}"
            shift # past argument
            bash ${docker_script} $@
            # exit neatly
            break
            ;;
        -v|--vscode)
            # update the vscode settings
            update_vscode_settings
            shift # past argument
            # exit neatly
            break
            ;;
        -d|--docs)
            # build the documentation
            echo "[INFO] Building documentation..."
            # retrieve the python executable
            python_exe=$(extract_python_exe)
            # install pip packages
            cd ${ISAACLAB_PATH}/docs
            if command -v uv &> /dev/null; then
                uv pip install -r requirements.txt > /dev/null
            else
                ${python_exe} -m pip install -r requirements.txt > /dev/null
            fi
            # build the documentation
            ${python_exe} -m sphinx -b html -d _build/doctrees . _build/current
            # open the documentation
            echo -e "[INFO] To open documentation on default browser, run:"
            echo -e "\n\t\txdg-open $(pwd)/_build/current/index.html\n"
            # exit neatly
            cd - > /dev/null
            shift # past argument
            # exit neatly
            break
            ;;
        -h|--help)
            print_help
            exit 1
            ;;
        *) # unknown option
            echo "[Error] Invalid argument provided: $1"
            print_help
            exit 1
            ;;
    esac
done
