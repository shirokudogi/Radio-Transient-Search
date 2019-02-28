#!/bin/bash
#
# utils.sh
#
# Created by:     Cregg C. Yancey
# Creation date:  October 11 2018
#
# Modified by:
# Modified date:
#
# PURPOSE: Implement utility functions used in shell scripts.
#

# Utility function for deleting specified files.
function delete_files()
{
   local FILES=("${@}")

   for curr in ${FILES[*]}
   do
      if [ -f "${curr}" ]; then
         echo "Deleting ${curr}"
         rm -f "${curr}"
      else
         echo "${curr} not found or is not a file"
      fi
   done
   return 0
}
# end delete_files()


# Utility function to move all files from source directory to destination directory.
function transfer_files()
{
   local SRC_DIR="."
   local DEST_DIR="."
   local FILES=

   # Parse commandline.
   if [ ${#} -gt 0 ]; then
      while [ -n "${1}" ]
      do
         case "${1}" in
            -s | --src-dir)
               SRC_DIR="${2}"
               shift; shift
               ;;
            -d | --dest-dir)
               DEST_DIR="${2}"
               shift; shift
               ;;
            *)
               FILES=("${*}")
               break
               ;;
         esac
      done
   fi

   # Check that the source and destination directories exist before proceding further.
   if [ -d "${SRC_DIR}" -a -d "${DEST_DIR}" ]; then
      # Check if we have a list of files to transfer.
      if [ -z "${FILES[*]}" ]; then
         # If no particular files specified, then transfer everything in the source directory.
         FILES=$(basename "${SRC_DIR}/*")
      else
         # If we are not in the source directory, then we will need to make sure we have an explicit list
         # of all the files to be moved.
         if [[ $(pwd) != "${SRC_DIR}" ]]; then
            pushd "${SRC_DIR}" 1>/dev/null
            FILES=$(ls ${FILES[*]} 2>/dev/null)
            popd 1>/dev/null
         fi
      fi

      if [[ "${SRC_DIR}" != "${DEST_DIR}" ]]; then
         echo "Transferring files from ${SRC_DIR} to ${DEST_DIR}..."
         for curr in ${FILES[*]}
         do
            echo "Moving ${curr}"
            mv "${SRC_DIR}/${curr}" "${DEST_DIR}/${curr}" 2>/dev/null
         done
      fi
   else
      if [ ! -d "${SRC_DIR}" ]; then
         echo "Source directory ${SRC_DIR} does not exist or is not a directory."
      fi
      if [ ! -d "${DEST_DIR}" ]; then
         echo "Destination directory ${DEST_DIR} does not exist or is not a directory."
      fi
      return 1
   fi
   
   return 0
}
# end transfer_files()
