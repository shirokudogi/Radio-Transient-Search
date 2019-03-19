
import os
import sys
import traceback
import numpy as np
from scipy.sparse import coo_matrix, csr_matrix
import apputils
from optparse import OptionParser

def create_spectrum(freqs, spectralIndex):
   """ Creates a normalized spectrum with specified spectral index.  Random fluctuations are added to
   introduced about the spectral curve fit. """

   spectrum = freqs**spectralIndex
   spectrum = spectrum/np.sum(spectrum)
   return spectrum
# end create_spectrum()

def create_injections(freqs, channelWidth, numIntervals, intervalTime, totalPower, spectralIndex,
                      temporalProfile=(None, None), DMProfile=(None, None), numInjects=1,
                      regularTimes=False, regularDMs=False, root=-1):
   """ Creates a spectrogram of dispersed, simulated signals with time resolution specified by
   intervalTime.  This spectrogram is built using a sparse matrix (to save space). """

   numInjects = np.floor(numInjects)
   injSpectrogram = None

   if numInjects > 0:
      numFreqs = len(freqs)
      topFreq = freqs[-1] + channelWidth
      invTopFreqSqrd = 1.0/(topFreq**2)
      invChannelWidth = 1.0/channelWidth

      maxTime = intervalTime*numIntervals
      timeStart = temporalProfile[0]
      timeEnd = temporalProfile[1]
      DMStart = DMProfile[0]
      DMEnd = DMProfile[1]
      invIntTime = 1.0/intervalTime

      # Compute injection spectrum.
      injSpectrum = totalPower*create_spectrum(freqs, spectralIndex)

      # Set temporal bounds for injections.
      if timeStart is None:
         timeStart = 0.0
      # endif
      if timeEnd is None:
         timeEnd = numIntervals*intervalTime
      # endif
      timeStart = apputils.clipValue(timeStart, 0.0, maxTime, np.float32)
      timeEnd = apputils.clipValue(timeEnd, 0.0, maxTime, np.float32), 
      #
      # Create times of injections.
      if regularTimes is True:
         injTimes = np.linspace(np.float32(timeStart), np.float32(timeEnd), np.float32(numInjects))
      else:
         injTimes = np.random.random(numInjects).astype(np.float32)*(timeEnd - timeStart) + timeStart
      # endif
      # Scale the injection times to the interval time.
      injTimesPrime = injTimes/intervalTime
     
      # Set DM bounds for injections.
      if not (DMStart is None and DMEnd is None):
         if DMEnd is None:
            DMEnd = DMStart
         else:
            DMStart = DMEnd
         # endif
         DMStart = apputils.clipValue(DMStart, 0.0, 5000.0, np.float32)
         DMEnd = apputils.clipValue(DMEnd, 0.0, 5000.0, np.float32)
      else:
         DMStart = 0.0
         DMEnd = 5000.0
      # endif
      # Create injection DMs.
      if regularDMs is True:
         injDMs = np.linspace(np.float32(DMStart), np.float32(DMEnd), np.float32(numInjects) )
      else:
         injDMs = np.random.random(numInjects)*(DMEnd - DMStart) + DMStart
      # endif

      # Compute indices and scaled delay times.
      injIndices = np.arange(numInjects, dtype=np.int32)
      freqIndices = np.arange(numFreqs, dtype=np.int32)
      scaleDelays = apputils.scaleDelays(freqs, topFreq)/intervalTime

      apputils.procMessage('waterfallinject.py: Determining data size needed for injection sparse matrix.',
                           root=root)
      # Compute the total number of data elements we will have.  Need this for constructing the sparse
      # matrix that will hold the injection spectrogram.
      dataCount = 0
      qSpans = np.zeros(numFreqs, dtype=np.int32)
      mIndices = np.zeros(numFreqs + 1, dtype=np.int32)
      maxQIndices = 0
      for i in injIndices:
         mIndices[0:numFreqs] = np.floor(scaleDelays[0:numFreqs]*injDMs[i] + \
                                          injTimesPrime[i]).astype(np.int32)
         mIndices[numFreqs] = np.floor(injTimesPrime[i]).astype(np.int32)
         qSpans[0:numFreqs] = (mIndices[0:numFreqs] - mIndices[1:numFreqs + 1]) + 2
         maxQIndices = np.maximum(maxQIndices, qSpans[0])
         dataCount += np.sum(qSpans)
         # endfor
      # endfor
      # Allocate sparse data arrays for sparse matrix.
      rows = apputils.create_NUMPY_memmap((dataCount, ), dtype=np.int32)
      cols = apputils.create_NUMPY_memmap((dataCount, ), dtype=np.int32)
      data = apputils.create_NUMPY_memmap((dataCount, ), dtype=np.float32)
      qOffset = 0 # Offset into the sparse data arrays.

      apputils.procMessage('waterfallinject.py: Compiling data for injection sparse matrix.', root=root)
      qIndices = np.arange(maxQIndices, dtype=np.int32)
      innerTimes = np.zeros(maxQIndices, dtype=np.float32)
      innerFreqs = np.zeros(maxQIndices, dtype=np.float32)
      weights = np.zeros(maxQIndices, dtype=np.float32)
      # For each injection, compute the dispersed power at each time and frequency.
      for i in injIndices:
         apputils.procMessage('waterfallinject.py: Compiling data for injection ' + \
                              '{0:d} of {1:d}.'.format(np.int(i+1), np.int(numInjects)), root=root)
         T0 = injTimes[i]
         T0Prime = injTimesPrime[i]
         kFactor = 4.148808e3*injDMs[i]

         mIndices[0:numFreqs] = np.floor(scaleDelays*injDMs[i] + T0Prime).astype(np.int32)
         mIndices[numFreqs] = np.floor(T0Prime).astype(np.int32)
         qSpans[0:numFreqs] = mIndices[0:numFreqs] - mIndices[1:(numFreqs + 1)]

         # Determine the dispersed power of each frequency channel for the current injection.
         for j in freqIndices:
            qSpan = qSpans[j]
            if qSpan > 0:
               # Determine inner time intervals and frequencies within the channel intersecting the
               # dispersion curve.
               innerTimes[0:qSpan] = intervalTime*(mIndices[j + 1] + 1 + qIndices[0:qSpan]) - T0
               innerFreqs[0:qSpan] = np.sqrt(1.0/(innerTimes[0:qSpan]/kFactor + invTopFreqSqrd))

               # Determine dispersion weights for each time interval along the dispersion curve within
               # the channel.
               if j == (numFreqs - 1):
                  weights[0] = invChannelWidth*(topFreq - innerFreqs[0])
               else:
                  weights[0] = invChannelWidth*(freqs[j + 1] - innerFreqs[0])
               # endif
               weights[1:qSpan] = invChannelWidth*(innerFreqs[0:(qSpan - 1)] - innerFreqs[1:qSpan])
               weights[qSpan] = invChannelWidth*(innerFreqs[qSpan - 1] - freqs[j])

               # Determine row indices for sparse matrix data and mask off any that exceed the dimensions
               # of the matrix.
               endIndex = np.minimum(qOffset + qSpan + 1, dataCount)
               qSpan = np.minimum(qSpan + 1, endIndex - qOffset)
               rowIndices = mIndices[j+1] + qIndices[0:qSpan]
               mask = rowIndices < numIntervals
               # Populate sparse matrix data for current channel.
               rows[qOffset:endIndex][mask] = rowIndices[0:qSpan][mask]
               cols[qOffset:endIndex][mask] = j
               data[qOffset:endIndex][mask] = weights[0:qSpan][mask]*injSpectrum[j] 
            else:
               qSpan = 1
               rows[qOffset] = mIndices[j+1]
               cols[qOffset] = j
               data[qOffset] = injSpectrum[j] 
            # endif
            #
            # Prepare for the next set of weighted data.
            qOffset = qOffset + qSpan
         # endfor
      # endfor
      #
      # Construct the simulated signal spectrogram as a sparse matrix from the dispersed power data.
      apputils.procMessage('waterfallinject.py: Constructing injection sparse matrix.', root=root)
      injSpectrogram = coo_matrix((data, (rows, cols)), shape = (numIntervals, numFreqs)).tocsr()
      apputils.procMessage('waterfallinject.py: Construction of injection sparse matrix complete.',
                           root=root)
   # endif
 
   return injSpectrogram
   
# end create_injection()
