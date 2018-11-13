import os
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from optparse import OptionParser

from apputils import forceIntValue

# Setup and parse commandline.
usage="Usage: %prog [options] <waterfall file>"
cmdlnParser = OptionParser(usage=usage)
cmdlnParser.add_option('-l', '--lower-cutoff',dest='lowerCutoff', default=0, type='int',
                        action='store',
                        help='Lower FFT index (between 0 and 4095) for the bandpass.',
                        metavar='INDEX')
cmdlnParser.add_option('-u', '--upper-cutoff',dest='upperCutoff', default=4095, type='int',
                        action='store',
                        help='Upper FFT index (between 0 and 4095) for the bandpass.',
                        metavar='INDEX')
cmdlnParser.add_option('-o', '--outfile', dest='outFilename', default='bandpass.png', type='string',
                        action='store',
                        help='Filename of the output PNG file.', metavar='NAME')
cmdlnParser.add_option("-w", "--work-dir", dest="workDir", default=".",
                       action="store",
                       help="Working directory path.", metavar="PATH")
(cmdlnOpts, cmdlnArgs) = cmdlnParser.parse_args()

# Check that a spectrogram file has been provided and that it exists.
if len(cmdlnArgs[0]) > 0:
   if not os.path.exists(cmdlnArgs[0]):
      print('Cannot find the spectrogram file \'{path}\''.format(path=cmdlnArgs[0]))
      exit(1)
   # endif
else:
   print('A path to a spectrogram file must be given.')
   exit(1)
# endif

# Force the FFT index values to be between 0 and 4095.
lowerCutoff = forceIntValue(cmdlnOpts.lowerCutoff, 0, 4095)
upperCutoff = forceIntValue(cmdlnOpts.upperCutoff, 0, 4095)
# Check that the lower FFT indice are less than the upper FFT indices.
if upperCutoff <= lowerCutoff:
   print('lower FFT index must be less than the upper FFT index.')
   exit(1)
# endif

# Create the bandpass image from the spectrogram.
spectrogram = np.load(cmdlnArgs[0], mmap_mode='r')
plt.plot(spectrogram[:,lowerCutoff:(upperCutoff + 1)].mean(0))
plt.suptitle('Bandpass', fontsize = 30)
plt.ylabel('Mean Power',fontdict={'fontsize':16})
plt.xlabel('Frequency',fontdict={'fontsize':14})
plt.savefig('{dir}/{name}'.format(dir=cmdlnOpts.workDir, name=cmdlnOpts.outFilepath))
plt.clf()
