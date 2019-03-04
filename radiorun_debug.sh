#!/bin/bash
#
# radiorun_debug.sh
#
# PURPOSE: Runs the radio transient search workflow on LWA using a debug search parameter configuration.
#


INSTALL_DIR="${HOME}/dev/radiotrans"
WORK_ROOT="/mnt/toaster/cyancey"
RESULTS_ROOT="${HOME}/analysis"
DATA_DIR="/data/network/recent_data/jtsai"
SEARCH_OPT=
#SEARCH_OPT="--do-dedispersed-search"


DATA_FILENAMES=("057974_001488582")
LABELS=("GWRDEBUG")

${INSTALL_DIR}/radiotrans_run.sh -I "${INSTALL_DIR}" -W "${WORK_ROOT}" -R "${RESULTS_ROOT}" \
                                 -D "${DATA_DIR}" --DEBUG ${SEARCH_OPT} \
                                 -A "${LABELS[0]}" "${DATA_FILENAMES[0]}"
