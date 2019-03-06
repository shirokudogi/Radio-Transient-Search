import os
import sys
import numpy as np
from ConfigParser import ConfigParser
from optparse import OptionParser
import apputils

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def main(args):
   # Setup and parse commandline.
   usage="Usage: %prog [options] <waterfall file>"
   cmdlnParser = OptionParser(usage=usage)
   cmdlnParser.add_option('-o', '--outfile', dest='outFilepath', default='./bandpass.png', type='string',
                           action='store',
                           help='Filepath of the output PNG file.', metavar='NAME')
   cmdlnParser.add_option("-w", "--work-dir", dest="workDir", default=".",
                          action="store",
                          help="Working directory path.", metavar="PATH")
   cmdlnParser.add_option("-l", "--label", dest="label", default='Coarse', type='string', action='store',
                           help='Label for the bandpass plot.', metavar='LABEL')
   cmdlnParser.add_option("-c", "--commconfig", dest="configFilepath", type="string",
                           default="./radiotrans.ini", action="store",
                           help="Path to the common parameters file.",
                           metavar="PATH")
   cmdlnParser.add_option("-b", "--baseline", dest="fPlotBaseline", default=False, action="store_true",
                           help="Flag denoting to produce a baseline plot instead of a bandpass plot.")
   cmdlnParser.add_option("-g", "--savitzky-golay", dest='SGParams', default=None, type='string',
                           action='store', help='Savitzky-Golay parameters', metavar='PARAMS')
   (cmdlnOpts, cmdlnArgs) = cmdlnParser.parse_args(args)

   # Check that a spectrogram file has been provided and that it exists.
   if len(cmdlnArgs[0]) > 0:
      if not os.path.exists(cmdlnArgs[0]):
         print 'bandpasscheck.py: ERROR => Cannot find the spectrogram file {path}'.format(path=cmdlnArgs[0])
         sys.exit(1)
      # endif
   else:
      print 'bandpasscheck.py: ERROR => A path to a spectrogram file must be given.'
      sys.exit(1)
   # endif

   # Read common parameters file for need common parameters and update with the RFI std cutoff.
   try:
      commConfigObj = ConfigParser()
      # Read current common parameters.
      configFile = open(cmdlnOpts.configFilepath,"r")
      commConfigObj.readfp(configFile, cmdlnOpts.configFilepath)
      samplerate = commConfigObj.getfloat('Raw Data', 'samplerate')
      numSamplesPerFrame = commConfigObj.getint('Raw Data', 'numsamplesperframe')
      decimation = commConfigObj.getint('Reduced DFT Data', 'decimation')
      integTime = commConfigObj.getfloat('Reduced DFT Data', 'integrationtime')
      numSpectLines = commConfigObj.getint('Reduced DFT Data', 'numspectrogramlines')
      configFile.close()
   except Exception as anError:
      print 'bandpasscheck.py: Could not read common parameters file {file}'.format(
               file= cmdlnOpts.configFilepath)
      print anError
      configFile.close()
      sys.exit(1)
   # endtry

   # Load spectrogram file.
   spectrogram = np.load(cmdlnArgs[0], mmap_mode='r')

   # Determine if we are making a bandpass or baseline plot.
   if not cmdlnOpts.fPlotBaseline:
      # Configure for bandpass plot.
      plotCurve = spectrogram.mean(0)
      freqStep = samplerate/(numSamplesPerFrame*1000.0)
      plotTitle = '{label} Bandpass'.format(label=cmdlnOpts.label)
      plotXLabel = 'Frequency ({step:.3f} kHz)'.format(step=freqStep)
   else:
      # Configure for baseline plot.
      plotCurve = spectrogram.mean(1)
      timeStep = integTime * int(numSpectLines/decimation)
      plotTitle = '{label} Baseline'.format(label=cmdlnOpts.label)
      plotXLabel = 'Time ({step:.4f} sec)'.format(step=timeStep)
   # endif

   # If Savitzky-Golay parameters are provided, perform Savitzky-Golay smoothing.
   if cmdlnOpts.SGParams is not None and len(cmdlnOpts.SGParams.split(',')) > 1:
      SGParams = [None, None]
      SGParams[:2] = [int(x) for x in cmdlnOpts.SGParams.split(',')[:2]]
      plotCurve = apputils.savitzky_golay(plotCurve, SGParams[0], SGParams[1])
   # endif

   plt.plot(plotCurve)
   plt.suptitle(plotTitle, fontsize = 28)
   plt.ylabel('Mean Power', fontdict={'fontsize':16})
   plt.xlabel(plotXLabel, fontdict={'fontsize':16})
   plt.savefig(cmdlnOpts.outFilepath)
   plt.clf()
# end main()
#

if __name__ == "__main__":
   main(sys.argv[1:])
   sys.exit(0)
# endif
