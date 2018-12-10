import os
import sys
import glob
import numpy as np
from optparse import OptParser
import ConfigParser
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
   cmdlnParser = OptParser()
   cmdlnParser.add_option("-o","--outfile", dest="outFilepath", type="string",
                           default="./coarsespectrogram.npy", action="store",
                           help="Path of the output coarse spectrogram file",
                           metavar="PATH")
   cmdlnParser.add_option("-i","--commconfig-file", dest="commConfigpath", type="string",
                           default="./config.ini", action="store",
                           help="Path to the common parameters file.",
                           metavar="PATH")
   cmdlnParser.add_options("-w", "--work-dir", dest="workDir", type="string",
                           default=".", action="store",
                           help="Path to the working directory.",
                           metavar="PATH")
   cmdlnParser.add_options("-c", "--commconfig", dest="configFilepath", type="string",
                           default="./radiotrans.ini", action="store",
                           help="Path to the common parameters file.",
                           metavar="PATH")
   # Parse command line
   (cmdlnOpts, tileFilepaths) = cmdlnParser.parse_args(argv)
   if len(tileFilepaths) == 0:
      print "Must provide paths to waterfall files to be combined."
      sys.exit(1)
   # endif
   tileFilepaths.sort()

   # Read common parameters file
   try:
      configFile = open(cmdlnOpts.configFilepath,"r")
      commConfigObj = ConfigParser.ConfigParser()
      commConfigObj.readfp(configFile, cmdlnOpts.commconfigpath)
      numSpectLines = commConfigObj.get('Reduced DFT Data', 'numspectrogramlines')
      DFTLength = commConfigObj.get('Reduced DFT Data', 'DFTlength')
      configFile.close()
   except:
      print 'Could not read common parameters configuration file: ', cmdlnOpts.commConfigpath
      configFile.close()
      sys.exit(1)
   # endtry

   # Create memory mapped array for combined waterfall.
   try:
      mmapSize = DFTLength*numSpectLines*np.dtype(np.float32).itemsize
      filename = '{dir}/tempcombwaterfall.dtmp'.format(dir=cmdlnOpts.workDir)
      tempSpectFile = open(filename, "w+b") 
      tempSpectFile.write('\0'*mmapSize)
      tempSpectFile.flush()
      mmapBuff = mmap.mmap(tempSpectFile.fileno(), mmapSize)
   except:
      print 'Could not create tempory memory mapped file for combined waterfall.'
      sys.exit(1)
   # endtry
   combWaterfall = np.ndarray(shape=(numSpectLines, DFTLength), dtype=np.float32, buffer=mmapBuff)

   # Load each waterfall file and add it to the final combined waterfall.
   beginIndex = 0
   for fileIndex in range(len(tileFilepaths)):
      try:
         waterfallTile = np.load(tileFilepaths[fileIndex])
      except:
         print 'Could not load waterfall file: ', tileFilepaths[fileIndex]
         sys.exit(1)
      # endtry

      numLines = len(waterfallTile)
      endIndex = fileIndex + numLines
      combWaterfall[beginIndex:endIndex, : ] = spectTile[:,:]
      beginIndex += numLines
   # endfor
   #
   # Save the final combined coarse waterfall.
   np.save(cmdlnOpt.coarseFilepath, Decimate(combWaterfall, int(combWaterfall.shape[0]/10000) ) )
# end main_radiotrans()

if __name__ == "__main__":
   # main_orig(sys.argv[1:])
   main_radiotrans(sys.argv[1:])
# endif
