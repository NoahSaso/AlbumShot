ARCHS = arm64 armv7

include theos/makefiles/common.mk

TWEAK_NAME = AlbumShot
AlbumShot_FILES = Tweak.xm ALAssetsLibrary+CustomPhotoAlbum.m
AlbumShot_FRAMEWORKS = UIKit AssetsLibrary

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
