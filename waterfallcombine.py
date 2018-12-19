import os
import sys
import glob
import numpy as np
from optparse import OptionParser
from ConfigParser import ConfigParser
import mmap
from apputils import Decimate



def main_orig(args):
   fn = sorted(glob.glob('waterfall05*.npy'))
   sp = np.zeros((len(fn),np.load(fn[0]).shape[0],np.load(fn[0]).shape[1]))
   for i in range(len(fn)):
       sp[i,:,:]=np.load(fn[i])

   np.save('waterfall',Decimate(sp, sp.shape[0]/4000))
# end main_orig()


def main_radiotrans(args):
   # Setup commandline options
   cmdlnParser = OptionParser()
   cmdlnParser.add_option("-o","--outfile", dest="outFilepath", type="string",
                           default="./coarsespectrogram.npy", action="store",
                           help="Path of the output coarse spectrogram file",
                           metavar="PATH")
   cmdlnParser.add_option("-i","--commconfig-file", dest="commConfigpath", type="string",
                           default="./config.ini", action="store",
                           help="Path to the common parameters file.",
                           metavar="PATH")
   cmdlnParser.add_option("-w", "--work-dir", dest="workDir", type="string",
                           default=".", action="store",
                           help="Path to the working directory.",
                           metavar="PATH")
   cmdlnParser.add_option("-c", "--commconfig", dest="configFilepath", type="string",
                           default="./radiotrans.ini", action="store",
                           help="Path to the common parameters file.",
                           metavar="PATH")
   # Parse command line
   (cmdlnOpts, tileFilepaths) = cmdlnParser.parse_args(args)
   if len(tileFilepaths) == 0:
      print "Must provide paths to waterfall files to be combined."
      sys.exit(1)
   # endif
   tileFilepaths.sort()

   # Read common parameters file
   try:
      configFile = open(cmdlnOpts.configFilepath,"r")
      commConfigObj = ConfigParser()
      commConfigObj.readfp(configFile, cmdlnOpts.configFilepath)
      numSpectLines = commConfigObj.getint('Reduced DFT Data', 'numspectrogramlines')
      DFTLength = commConfigObj.getint('Reduced DFT Data', 'DFTlength')
      configFile.close()
   except Exception as anError:
      print 'Could not read common parameters configuration file: ', cmdlnOpts.configFilepath
      print anError
      configFile.close()
      sys.exit(1)
   # endtry

   # Create memory mapped array for combined waterfall.
   try:
      mmapSize = DFTLength*numSpectLines*np.dtype(np.float32).itemsize
      tempFilepath = '{dir}/tempcombwaterfall.dtmp'.format(dir=cmdlnOpts.workDir)
      #tempSpectFile = open(tempFilepath, "w+b") 
      print 'waterfallcombine.py: Creating memmap array of size {size} bytes...'.format(size=mmapSize)
      combWaterfall = np.memmap(filename=tempFilepath, shape=(numSpectLines, DFTLength), 
                                 dtype=np.float32, mode='w')
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

   # Save the final combined coarse waterfall.
   print 'waterfallcombine.py: Decimating memmap to final combined coarse spectrogram...'
   np.save(cmdlnOpts.coarseFilepath, Decimate(combWaterfall, int(combWaterfall.shape[0]/10000) ) )
# end main_radiotrans()

if __name__ == "__main__":
   # main_orig(sys.argv[1:])
   main_radiotrans(sys.argv[1:])
# endif
