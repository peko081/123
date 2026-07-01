ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoClicker

AutoClicker_FILES = Tweak.xm Sources/AutoTouch.mm Sources/ACTouchEngine.m Sources/ACManager.m Sources/ACOverlayWindow.m
AutoClicker_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AutoClicker_FRAMEWORKS = UIKit CoreGraphics QuartzCore Foundation
AutoClicker_PRIVATE_FRAMEWORKS = IOKit

include $(THEOS)/makefiles/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard" || true
