"littoral-bench.st — the Seaside side of bench/compare.sh seaside.
 Seaside's own WACounter at /counter, a sushi store like
 littoral-examples:store at /store, /_stats as bench/load-server.lisp
 serves it, and littoral.js as a static file, from LtBenchFiles.  Filed in by bench/seaside/setup.sh."!

Object subclass: #LtCart
	instanceVariableNames: 'lines'
	classVariableNames: ''
	package: 'Littoral-Bench'!

WATableReport subclass: #LtPagedReport
	instanceVariableNames: 'batcher'
	classVariableNames: ''
	package: 'Littoral-Bench'!

WAComponent subclass: #LtCartView
	instanceVariableNames: 'cart'
	classVariableNames: ''
	package: 'Littoral-Bench'!

WAComponent subclass: #LtStore
	instanceVariableNames: 'cart report cartView'
	classVariableNames: ''
	package: 'Littoral-Bench'!

WAFileLibrary subclass: #LtBenchFiles
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Littoral-Bench'!

WARequestHandler subclass: #LtStatsHandler
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Littoral-Bench'!

!LtCart class methodsFor: 'formatting'!
money: cents
	^ '$', (cents // 100) printString, '.', ((cents \\ 100) printPaddedWith: $0 to: 2)! !

!LtCart methodsFor: 'accessing'!
initialize
	super initialize.
	lines := #()!
lines
	^ lines!
quantity
	^ lines inject: 0 into: [ :sum :line | sum + line value ]!
total
	^ lines inject: 0 into: [ :sum :line | sum + (line key second * line value) ]! !

!LtCart methodsFor: 'changing'!
add: dish
	"A new array each time: Seaside's snapshot of the cart is a shallow copy."
	(lines anySatisfy: [ :line | line key == dish ])
		ifTrue: [ lines := lines collect: [ :line |
				line key == dish ifTrue: [ dish -> (line value + 1) ] ifFalse: [ line ] ] ]
		ifFalse: [ lines := lines copyWith: dish -> 1 ]!
remove: dish
	lines := lines reject: [ :line | line key == dish ]! !

!LtPagedReport methodsFor: 'paging'!
initialize
	super initialize.
	batcher := WABatchedList new batchSize: 8; yourself!
rows: aCollection
	super rows: aCollection.
	batcher items: aCollection!
rows
	| all |
	all := super rows.
	^ all copyFrom: batcher startIndex to: (batcher endIndex min: all size)!
children
	^ Array with: batcher!
renderContentOn: html
	super renderContentOn: html.
	html render: batcher! !

!LtCartView methodsFor: 'rendering'!
cart: aCart
	cart := aCart!
renderContentOn: html
	html aside class: 'cart'; with: [
		html heading level: 2; with: 'Cart'.
		cart lines isEmpty
			ifTrue: [ html paragraph class: 'empty'; with: 'Nothing yet.' ]
			ifFalse: [
				html unorderedList: [
					cart lines do: [ :line |
						html listItem: [
							html text: line value printString, ' × ', line key first; space.
							html anchor title: 'Remove'; callback: [ cart remove: line key ]; with: '✕' ] ] ].
				html paragraph: [ html text: 'Total '. html strong: (LtCart money: cart total) ].
				html anchor class: 'checkout'; callback: [ ]; with: 'Checkout »' ] ]! !

!LtStore class methodsFor: 'menu'!
menu
	^ #(#('Maguro nigiri' 450 'Tuna on rice') #('Sake nigiri' 400 'Salmon on rice')
		#('Hamachi nigiri' 500 'Yellowtail on rice') #('Unagi nigiri' 550 'Grilled eel, sweet glaze')
		#('Ebi nigiri' 380 'Cooked prawn on rice') #('Tamago nigiri' 300 'Sweet omelette')
		#('California roll' 750 'Crab, avocado, cucumber') #('Spicy tuna roll' 800 'Tuna, chilli mayonnaise')
		#('Kappa maki' 450 'Cucumber') #('Dragon roll' 1250 'Eel and avocado')
		#('Salmon sashimi' 1100 'Six slices') #('Miso soup' 300 'With tofu and wakame')
		#('Edamame' 400 'Salted soy beans') #('Green tea' 250 'Pot for one'))! !

!LtStore methodsFor: 'initialization'!
initialize
	super initialize.
	cart := LtCart new.
	cartView := LtCartView new cart: cart; yourself.
	report := LtPagedReport new.
	report columns: (Array
		with: (WAReportColumn new title: 'Dish'; valueBlock: [ :dish | dish first ]; yourself)
		with: (WAReportColumn new title: ''; valueBlock: [ :dish | dish third ]; sortBlock: nil; yourself)
		with: (WAReportColumn new title: 'Price'; cssClass: 'number'; valueBlock: [ :dish | dish second ];
				formatBlock: [ :price | LtCart money: price ]; yourself)
		with: (WAReportColumn renderBlock: [ :dish :html |
				html anchor class: 'add'; callback: [ cart add: dish ]; with: 'Add' ] title: '')).
	report rows: self class menu! !

!LtStore methodsFor: 'rendering'!
children
	^ Array with: report with: cartView!
states
	^ Array with: cart!
renderContentOn: html
	| quantity |
	quantity := cart quantity.
	html header class: 'store-header'; with: [
		html heading: 'Sushi Store'.
		html span class: 'cart-count';
			with: quantity printString, ' item', (quantity = 1 ifTrue: [ '' ] ifFalse: [ 's' ]), ' in your cart' ].
	html div class: 'store-body'; with: [
		html section class: 'menu'; with: [ html render: report ].
		html render: cartView ]!
style
	^ '.store-header { display: flex; flex-wrap: wrap; gap: .4rem 1rem; justify-content: space-between; align-items: baseline; }
.store-body { display: grid; grid-template-columns: minmax(0, 1fr) 16rem; gap: 1.5rem; align-items: start; }
.cart { border: 1px solid #ccc; border-radius: 6px; padding: .2rem 1rem 1rem; }
.cart ul { padding-left: 1rem; } .cart a { text-decoration: none; }'! !

!LtStatsHandler methodsFor: 'handling'!
handleFiltered: aRequestContext
	| sessions json |
	Smalltalk garbageCollect.
	sessions := 0.
	WAAdmin defaultDispatcher handlers do: [ :each |
		each isApplication ifTrue: [ sessions := sessions + each cache size ] ].
	json := String streamContents: [ :out |
		out nextPutAll: '{"heap":';
			print: Smalltalk vm oldSpace - Smalltalk vm freeOldSpaceSize;
			nextPutAll: ',"sessions":'; print: sessions;
			nextPutAll: ',"streams":0,"threads":'; print: Process allInstances size;
			nextPutAll: '}' ].
	aRequestContext respond: [ :response |
		response contentType: 'application/json'; nextPutAll: json ]! !

!ZnNetworkingUtils class methodsFor: '*Littoral-Bench'!
listenBacklogSize
	"Zinc's is 32; this is macOS's limit (kern.ipc.somaxconn), as Hunchentoot's 50 is under it."
	^ 128! !

!LtStatsHandler class methodsFor: 'starting'!
startOn: port
	"Serve Seaside on PORT, allowing as many connections as littoral's load server has threads."
	| adaptor |
	"Each socket takes three semaphores, and the table (256) isn't saved with the image."
	Smalltalk vm maxExternalSemaphoresSilently: 65535.
	adaptor := ZnZincServerAdaptor port: port.
	adaptor start.
	adaptor server maximumNumberOfConcurrentConnections: 1000! !
