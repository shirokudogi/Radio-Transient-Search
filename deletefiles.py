import os
import sys
import glob
from optparse import OptionParser

usage = 'USAGE: %prog [options] <other files>'
cmdlnParser = OptionParser()
cmdlnParser.add_option('-d', '--file-dir', dest='fileDir', default='.',
                        type='string', action='store',
                        help='Path of directory containing files to be deleted.',
                        metavar='PATH')
cmdlnParser.add_option('-w', '--waterfall', dest='fWaterfall', default=False,
                        action='store_true', help='Flag denoting to delete reduced-data waterfall files.')
cmdlnParser.add_option('-c', '--coarse-waterfall', dest='fCoarse', default=False,
                        action='store_true', help='Flag denoting to delete coarse waterfall files.')
cmdlnParser.add_option('-i','--images', dest='fImages', default=False, action='store_true',
                        help='Flag denoting to delete image files.')
cmdlnParser.add_option('-s', '--supplemental', dest='fSupplemental', default=False, action='store_true', 
                        help='Flag denoting to delete supplemental files.')
cmdlnParser.add_option('-t', '--temporary', dest='fTemporary', default=False,
                        action='store_true', 
                        help='Flag denoting to delete temporary files.')
cmdlnParser.add_option('-a', '--all', dest='fAll', default=False,
                        action='store_true', help='Flag denoting to delete all radio transient files.')
(cmdlnOpts, otherFiles) = cmdlnParser.parse_args()                        
fileDir = cmdlnOpts.fileDir

if len(otherFiles) > 0:
   myFiles = otherFiles
else:
   myFiles = []
# endif

if cmdlnOpts.fWaterfall or cmdlnOpts.fAll:
   myFiles = myFiles + glob.glob('{dir}/waterfall*.npy'.format(dir=fileDir))
# endif

if cmdlnOpts.fImages or cmdlnOpts.fAll:
   myFiles = myFiles + glob.glob('{dir}/*.png'.format(dir=fileDir))
# endif

if cmdlnOpts.fCoarse or cmdlnOpts.fAll:
   myFiles = myFiles + glob.glob('{dir}/coarsewaterfall*.npy'.format(dir=fileDir)) 
# endif

if cmdlnOpts.fSupplemental or cmdlnOpts.fAll:
   myFiles = myFiles + ['{dir}/tInt.npy'.format(dir=fileDir)] + \
               glob.glob('{dir}/*.ini'.format(dir=fileDir)) + \
               glob.glob('{dir}/*tunefreq.npy'.format(dir=fileDir))
# endif

if cmdlnOpts.fTemporary or cmdlnOpts.fAll:
   myFiles = myFiles + glob.glob('{dir}/*.dtmp'.format(dir=fileDir))
# endif

nCount = 0
numFiles = len(myFiles)
for filepath in myFiles:
   if os.path.exists(filepath):
      print 'Attempting to remove', filepath
      os.remove(filepath)
      if not os.path.exists(filepath):
         nCount = nCount + 1
         print 'Removal SUCCESS'
      else:
         print 'Removal FAIL'
      # endif
   else:
      numFiles = numFiles - 1
   # endif
# end for

print 'Successfully removed', nCount, 'files of', numFiles
