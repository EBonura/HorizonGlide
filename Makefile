.PHONY: export run

PICO8 = /Users/ebonura/Desktop/pico-8/PICO-8.app/Contents/MacOS/pico8
CART  = v0.22.p8

export:
	$(PICO8) $(CART) -export export/horizon-glide.html
	cd export && mv horizon-glide.html index.html

run:
	$(PICO8) -run $(CART)
