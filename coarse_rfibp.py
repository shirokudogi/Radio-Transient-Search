import os
import sys
import glob
import tempfile
import numpy as np
from optparse import OptionParser
from ConfigParser import ConfigParser
import mmap
import apputils



def main(args):
   # Setup commandline options
   cmdlnParser = OptionParser()
   cmdlnParser.add_option("-o","--outfile", dest="outFilepath", type="string",
                           default="./spectrogram.npy", action="store",
                           help="Path of the output coarse spectrogram file",
                           metavar="PATH")
   cmdlnParser.add_option("-i","--image-file", dest="imageFilepath", type="string",
                           default="./coarsespectrogram.png", action="store",
                           help="Path to the coarse spectrogram image file.",
                           metavar="PATH")
   cmdlnParser.add_option("-w", "--work-dir", dest="workDir", type="string",
                           default=".", action="store",
                           help="Path to the working directory.",
                           metavar="PATH")
   cmdlnParser.add_option("-c", "--commconfig", dest="configFilepath", type="string",
                           default="./radiotrans.ini", action="store",
                           help="Path to the common parameters file.",
                           metavar="PATH")
   cmdlnParser.add_option("-d", "--decimation", dest="decimation", type="int", default=10000,
                           action="store", help="Decimation number for coarse spectrogram.", 
                           metavar="NUM")
   # Parse command line
   (cmdlnOpts, inFilepath) = cmdlnParser.parse_args(args)
   if len(inFilepath) == 0:
      print "Must provide path to RFI-bandpass spectrogram file."
      sys.exit(1)
   # endif

   # Load RFI-bandpass filtered spectrogram file into memory-mapped array.
   try:
      print 'coarse_rfibp.py: Loading RFI-bandpass spectrogram...'
      spectrogram = np.load(inFilepath[0], mmap_mode='r')
   except Exception as anError:
      print 'Could not load spectrogram file: ', tempFilepath
      print anError
      sys.exit(1)
   # endtry
   #
   # Save the coarse version of the spectrogram.
   print 'coarse_rfibp.py: Writing coarse RFI-bandpass spectrogram...'
   decimateFactor = np.int(spectrogram.shape[0]/cmdlnOpts.decimation)
   np.save(cmdlnOpts.outFilepath, apputils.DecimateNPY(spectrogram, decimateFactor))
# end main_radiotrans()

if __name__ == "__main__":
   main(sys.argv[1:])
   sys.exit(0)
# endif
