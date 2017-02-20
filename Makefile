ARCHS = arm64 armv7

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AlbumShot
AlbumShot_FILES = Tweak.xm
AlbumShot_FRAMEWORKS = UIKit AssetsLibrary Photos
AlbumShot_CFLAGS = -Wno-deprecated-declarations -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
