#!/bin/bash
#
# radiocleague.sh
#
# Created by:     Cregg C. Yancey
#
# Purpose: Simple script to create spectrogram images using the code imported from Chris League's
#          repository for Radio-Transient-Search => https://github.com/league/Radio-Transient-Search
#
shopt -s extglob

NPROCS=$(nproc --all)
INSTALL_DIR="${HOME}/dev/radioCLeague"
WORK_DIR="/mnt/toaster/cyancey/GWRDEBUG_CLEAGUE"

DATA_DIR="/data/network/recent_data/jtsai"
DATA_FILE="057974_001488582"
DATA_PATH="${DATA_DIR}/${DATA_FILE}"

# Ensure that the working directory exists.
if [ ! -d "${WORK_DIR}" ]; then
   mkdir "${WORK_DIR}"
   if [ ! -d "${WORK_DIR}" ]; then
      echo "radiocleague.sh: ERROR => could not find or create working directory ${WORK_DIR}"
      exit 1
   fi
fi


# Source the resume functionality and custom utilities.
RESUME_CMD_FILEPATH="${WORK_DIR}/radiocleague_cmd.resume"
RESUME_VAR_FILEPATH="${WORK_DIR}/radiocleague_var.resume"
source "${INSTALL_DIR}/resume.sh"
source "${INSTALL_DIR}/utils.sh"

# If we are not already in the working directory, then temporarily change to it.
CURR_DIR=$(pwd)
if [[ "${CURR_DIR}" != "${WORK_DIR}" ]]; then
   pushd "${WORK_DIR}"
fi

# Create spectrogram.
resumecmd -l "WATERFALL" mpirun -np ${NPROCS} python "${INSTALL_DIR}/waterfall.py" "${DATA_PATH}"
resumecmd -l "COMBINE" -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python "${INSTALL_DIR}/waterfallcombine.py"
resumecmd -l "WATCH" -k ${RESUME_LASTCMD_SUCCESS} \
   mpirun -np 1 python "${INSTALL_DIR}/watchwaterfall.py" 5.0 CLeague

# Clean up waterfall files.  We only want to keep the coarse combined spectrogram waterfall file.
resumecmd -l "CLEAN" -k ${RESUME_LASTCMD_SUCCESS} \
   delete_files "${WORK_DIR}/waterfall${DATA_FILE}*.npy"

# Change back to the previous directory, if we changed directories previously.
if [[ "${CURR_DIR}" != "${WORK_DIR}" ]]; then
   popd
fi
