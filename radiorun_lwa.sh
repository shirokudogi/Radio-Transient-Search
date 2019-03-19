#!/bin/bash
#
# radiorun_lwa.sh
#
# PURPOSE: Runs the radio transient search workflow on LWA.
#

while [ ! -z "${1}" ]
do
   if [[ "${1}" == "--clean" ]]; then
      CLEAN_RUN_OPT="--clean"
   fi
   shift
done

INSTALL_DIR="${HOME}/local/radiotrans"
WORK_ROOT="/mnt/toaster/cyancey"
RESULTS_ROOT="${HOME}/analysis"
DATA_DIR="/data/network/recent_data/jtsai"


DATA_FILENAMES=("057974_001488582")
LABELS=("GWR170809B2")
PARAM_FILE="./run_params.comm"

${INSTALL_DIR}/radiotrans_run.sh -I "${INSTALL_DIR}" -W "${WORK_ROOT}" -R "${RESULTS_ROOT}" \
                                 -D "${DATA_DIR}" --GW170809 --skip-rfi-bandpass \
                                 -P "${PARAM_FILE}" ${CLEAN_RUN_OPT} \
                                 --delete-waterfalls \
                                 -A "${LABELS[0]}" "${DATA_FILENAMES[0]}"
