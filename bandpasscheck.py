import numpy as np
import matplotlib
# Force matplotlib to not use any Xwindows backend.
matplotlib.use('Agg')
import matplotlib.pyplot as plt

sp = np.load('waterfall.npy')
plt.plot(sp[:,0,:].mean(0))
plt.suptitle('Bandpass Low Tuning', fontsize = 30)
plt.ylabel('Intensity',fontdict={'fontsize':16})
plt.xlabel('Frequency',fontdict={'fontsize':14})
#plt.show()
plt.savefig('bandpass-low')

plt.plot(sp[:,1,:].mean(0))
plt.suptitle('Bandpass High Tuning', fontsize = 30)
plt.ylabel('Intensity',fontdict={'fontsize':16})
plt.xlabel('Frequency',fontdict={'fontsize':14})
plt.show()
plt.savefig('bandpass-high')
