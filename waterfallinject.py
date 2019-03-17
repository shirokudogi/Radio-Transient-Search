
import os
import sys
import numpy as np
from scipy.sparse import coo_matrix, csr_matrix
import apputils
from optparse import OptionParser

def create_spectrum(freqs, spectralIndex)
   """ Creates a normalized spectrum with specified spectral index.  Random fluctuations are added to
   introduced about the spectral curve fit. """

   spectrum = (1 + 0.2*np.random(len(freqs)))*freqs**spectralIndex
   spectrum = spectrum/np.sum(spectrum)
   return spectrum
# end create_spectrum()

def create_injection(freqs, channelWdith, numIntervals, intervalTime, totalPower, spectralIndex,
                     temporalProfile=(None, None), DMProfile=(None, None), numInjects=1,
                     regularTimes=False, regularDMs=False):
   """ Creates a spectrogram of dispersed, simulated signals with time resolution specified by
   intervalTime.  This spectrogram is built using a sparse matrix (to save space). """

   numInjects = np.floor(numInjects)
   injSpectrogram = None

   if numInjects > 0:
      numFreqs = len(freqs)
      topFreq = freqs[-1] + channelWidth
      topFreqSqrd = topFreq**2
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
         injTimes = np.linspace(timeStart, timeEnd, numInjects, dtype=np.float64) 
      else:
         injTimes = np.random(numInjects)*(timeEnd - timeStart) + timeStart
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
         injDMs = np.linspace(DMStart, DMEnd, numInjects, dtype=np.float64)
      else:
         injDMs = np.random(numInjects)*(DMEnd - DMStart) + DMStart
      # endif

      # Compute indices and scaled delay times.
      injIndices = np.arange(numInjects)
      freqIndices = np.arange(numFreqs))
      scaleDelays = apputils.scaleDelays(freqs, topFreq)/intervalTime

      # Compute the total number of data elements we will have.  Need this for constructing the sparse
      # matrix that will hold the injection spectrogram.
      dataCount = 0
      counts = np.zeros(numFreqs, dtype=np.int32)
      maxTIndices = 0
      for i in injIndices:
         counts[-1] = np.floor(injTimesPrime[i]).astype(np.int32) - 
                      np.floor(scaleDelays[-1]*injDMs[i] + injTimesPrime[i]).astype(np.int32)
         counts[0:-1] = np.floor(scaleDelays[0:-1]*injDMs[i] + injTimesPrime[i]).astype(np.int32) - 
                  np.floor(scaleDelays[1:]*injDMs[i] + injTimesPrime[i]).astype(np.int32)
         maxTIndices = np.maximum(numTIndices, counts[0])
         dataCount += np.sum(counts)
         # endfor
      # endfor
      # Allocate sparse data arrays for sparse matrix.
      rows = np.zeros(dataCount, dtype=np.int32)
      cols = np.zeros(dataCount, dtype=np.int32)
      data = np.zeros(dataCount, dtype=np.float32)
      qOffset = 0 # Offset into the sparse data arrays.

      # Compute sparse data for dispersed simulated signal spectrogram.
      # Pre-allocate compute arrays that will be used in building up the sparse data.
      qIndices = np.arange(maxTIndices, dtype=np.int32)
      innerTimes = np.zeros(maxTIndices, dtype=np.float32)
      innerFreqs = np.zeros(maxTIndices, dtype=np.float32)
      weights = np.zeros(maxTIndices, dtype=np.float32)
      # For each injection, compute the dispersed power at each time and frequency.
      for i in injIndices:
         T0 = injTimes[i]
         kFactor = 4.148808e3*injDMs[i]
         fFactor = kFactor*topFreqSqrd
         # Compute the time-index containing the time of the top frequency of the top channel on the 
         # dispersion curve.
         mIndexPrior = np.floor(injTimesPrime[i]).astype(np.int32) 
         upperFreq = topFreq  # Upper frequency of the current channel.
         # Compute sparse data for each channel.
         for j in freqIndices:
            # Compute the time-index containing the time of the bottom frequency of the channel on the
            # dispersion curve.
            mIndex = np.floor(scaleDelays[j]*injDMs[i] + injTimesPrime[i]).astype(np.int32) 
            # Compute the times of intervals lying completely between the dispersed time of the top
            # frequency of the channel and the bottom frequency of the channel.
            qSpan = (mIndexPrior + 1 - mIndex) + 1 # Written like this for math clarity.
            innerTimes[0:qSpan] = intervalTime*(mIndexPrior + qIndices[0:qSpan])
            # Compute the frequencies on the dispersion curve at the interval times.
            innerFreqs[0:qSpan] = np.sqrt( fFactor/(topFreqSqrd*(innerTimes[0:qSpan] - T0) + kFactor) )
            # Compute the weights of dispersed power over each interval covered by the dispersion curve
            # in the current channel.
            weights[0] = invChannelWidth*(upperFreq - innerFreqs[0])
            weights[1:qSpan-1] = invChannelWidth*(innerFreqs[1:qSpan] - innerFreqs[0:qSpan-1])
            weights[qSpan - 1] = invChannelWidth*(innerFreqs[qSpan-1] - freqs[j])
            # Compute the sparse data for the channel.
            rows[qOffset: qOffset + qSpan] = mIndexPrior + qIndices[0:qSpan]
            cols[qOffset: qOffset + qSpan] = j
            data[qOffset: qOffset + qSpan] = weights[0:qSpan]*injSpectrum[j] 
            
            # Prepare for the next channel.
            mIndexPrior = mIndex
            qOffset += qSpan
         # endfor
      # endfor
      #
      # Create the simulated signal spectrogram as a sparse matrix from the sparse data.
      injSpectrogram = coo_matrix((data, (rows, cols)), shape = (numIntervals, numFreqs)).tocsc()

   # endif
 
   return injSpectrogram
   
# end create_injection()
