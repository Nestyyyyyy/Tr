PKG ?= com.skgames.trafficracer
export PKG

.PHONY: help tools pull patch install prefs info all clean distclean

help:
	@echo "Traffic Racer - root'suz mod araç zinciri  (paket: $(PKG))"
	@echo
	@echo "  make tools     araçları indir (bir kere)"
	@echo "  make pull      APK'yı kendi telefonundan çek"
	@echo "  make patch     manifest'i yamala + imzala"
	@echo "  make install   orijinali kaldır, yamalıyı kur  (ilerleme silinir)"
	@echo "  make all       yukarıdaki dördü sırayla"
	@echo
	@echo "  make prefs     kayıt dosyasındaki anahtarları listele"
	@echo "  make info      motor tespiti (Mono / IL2CPP) - Plan B için"
	@echo "  make clean     ara dosyaları sil"
	@echo
	@echo "  Değer değiştirme:  ./tools/04-prefs.sh set <anahtar> <deger>"

tools:
	@./tools/00-fetch-tools.sh

pull:
	@./tools/01-pull.sh

patch:
	@./tools/02-patch.sh

install:
	@./tools/03-install.sh

prefs:
	@./tools/04-prefs.sh list

info:
	@./tools/05-engine-info.sh

all: tools pull patch install

clean:
	@rm -rf work/decoded work/unsigned.apk work/apk-listing.txt
	@echo "ara dosyalar temizlendi"

distclean: clean
	@rm -rf work out bin
	@echo "her sey temizlendi (bin/ dahil)"
