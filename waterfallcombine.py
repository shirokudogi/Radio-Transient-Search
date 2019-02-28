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
   cmdlnParser.add_option("-d", "--decimation", dest="decimation", type="int",
                           default=10000,
                           help="Decimation of the combined spectrogram to form a coarse version",
                           metavar="NUM")
   # Parse command line
   (cmdlnOpts, tileFilepaths) = cmdlnParser.parse_args(args)
   if len(tileFilepaths) == 0:
      print "Must provide paths to waterfall files to be combined."
      sys.exit(1)
   # endif
   tileFilepaths = apputils.sortWaterfallFilepaths(tileFilepaths)

   # Read common parameters file for need common parameters and update with the decimation factor.
   try:
      commConfigObj = ConfigParser()

      # Read current common parameters.
      configFile = open(cmdlnOpts.configFilepath,"r")
      commConfigObj.readfp(configFile, cmdlnOpts.configFilepath)
      numSpectLines = commConfigObj.getint('Reduced DFT Data', 'numspectrogramlines')
      DFTLength = commConfigObj.getint('Reduced DFT Data', 'dftlength')
      configFile.close()

      # Update common parameters with decimation factor.
      configFile = open(cmdlnOpts.configFilepath,"w")
      commConfigObj.set('Reduced DFT Data', 'decimation', cmdlnOpts.decimation)
      commConfigObj.write(configFile)
      configFile.close()
   except Exception as anError:
      print 'Could not read or update common parameters configuration file: ', cmdlnOpts.configFilepath
      print anError
      configFile.close()
      sys.exit(1)
   # endtry


   # Create memory mapped array for combined waterfall.
   try:
      mmapSize = DFTLength*numSpectLines*np.dtype(np.float32).itemsize
      (tempFD, tempFilepath) = tempfile.mkstemp(prefix='tmp', suffix='.dtmp', dir=cmdlnOpts.workDir)
      print 'waterfallcombine.py: Creating memmap array of size {size} bytes...'.format(size=mmapSize)
      combWaterfall = np.memmap(filename=tempFilepath, shape=(numSpectLines, DFTLength), 
                                 dtype=np.float32, mode='w+')
   except Exception as anError:
      print 'Could not create memmap array for combined waterfall: ', tempFilepath
      print anError
      sys.exit(1)
   # endtry

   # Load each waterfall file and add it to the final combined waterfall.
   beginIndex = 0
   for filepath in tileFilepaths:
      try:
         print 'waterfallcombine.py: Loading {path} into memmap array...'.format(path=filepath)
         waterfallTile = np.load(filepath)
      except:
         print 'Could not load waterfall file {path}.'.format(path=filepath)
         sys.exit(1)
      # endtry

      numLines = len(waterfallTile)
      endIndex = beginIndex + numLines
      combWaterfall[beginIndex:endIndex, : ] = waterfallTile[:,:]
      beginIndex += numLines
   # endfor
   combWaterfall.flush()

   # Save the final combined waterfall file.
   print 'waterfallcombine.py: Writing combined waterfall spectrogram...'
   np.save(cmdlnOpts.outFilepath, combWaterfall)
   # Save the coarse version of the combined waterfall file.
   print 'waterfallcombine.py: Writing coarse version of combined waterfall spectrogram...'
   (outDir, outFilename) = os.path.split(cmdlnOpts.outFilepath)
   if len(outDir) == 0:
      outDir = "."
   # endif
   np.save('{dir}/coarse-{name}'.format(dir=outDir, name=outFilename), 
            apputils.DecimateNPY(combWaterfall, int(combWaterfall.shape[0]/cmdlnOpts.decimation) ) )

   os.close(tempFD)
# end main_radiotrans()

if __name__ == "__main__":
   main(sys.argv[1:])
   sys.exit(0)
# endif
