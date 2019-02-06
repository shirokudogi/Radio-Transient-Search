#!/bin/bash
#
# radiocleague.sh
#
# Created by:     Cregg C. Yancey
#
# Purpose: Simple script to create spectrogram images using the code imported from Chris League's
#          repository for Radio-Transient-Search => https://github.com/league/Radio-Transient-Search
#

NPROCS=$(nproc --all)
INSTALL_DIR="${HOME}/dev/radioCLeague"
DATA_DIR="/data/network/recent_data/jtsai"
DATA_FILE="057974_001488582"
DATA_PATH="${DATA_DIR}/${DATA_FILE}"


mpirun -np ${NPROCS} python "${INSTALL_DIR}/waterfall.py" "${DATA_PATH}"
mpirun -np 1 python "${INSTALL_DIR}/waterfallcombine.py"
mpirun -np 1 python "${INSTALL_DIR}/watchwaterfall.py" 5.0 CLeague
