ARCHS = arm64 armv7
TARGET = iphone:9.3:7.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AlbumShot
AlbumShot_FILES = Tweak.xm
AlbumShot_FRAMEWORKS = UIKit AssetsLibrary Photos
AlbumShot_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
	# install.exec "killall -9 Camera"
