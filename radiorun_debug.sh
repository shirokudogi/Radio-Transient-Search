#!/bin/bash
#
# radiorun_debug.sh
#
# PURPOSE: Runs the radio transient search workflow on LWA using a debug search parameter configuration.
#

while [ ! -z "${1}" ]
do
   if [[ "${1}" == "--clean" ]]; then
      CLEAN_RUN_OPT="--clean"
   fi
   if [[ "${1}" == "--destroy" ]]; then
      DESTROY_OPT="--destroy"
   fi
   if [[ "${1}" == "--play-nice" ]]; then
      PLAY_NICE_OPT="--play-nice"
   fi
   shift
done

INSTALL_DIR="${HOME}/dev/radiotrans"
WORK_ROOT="/mnt/toaster/cyancey"
RESULTS_ROOT="${HOME}/analysis"
DATA_DIR="/data/network/recent_data/jtsai"
SEARCH_OPT="--do-dedispersed-search"


DATA_FILENAMES=("057974_001488582")
LABELS=("GWRDEBUG")
PARAM_FILE="./run_params.comm"

${INSTALL_DIR}/radiotrans_run.sh -I "${INSTALL_DIR}" -W "${WORK_ROOT}" -R "${RESULTS_ROOT}" \
                                 -D "${DATA_DIR}" --DEBUG ${SEARCH_OPT} --delete-waterfalls \
                                 -P "${PARAM_FILE}" ${CLEAN_RUN_OPT} ${DESTROY_OPT} \
                                 ${PLAY_NICE_OPT} \
                                 -A "${LABELS[0]}" "${DATA_FILENAMES[0]}"
