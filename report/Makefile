NAME=report

INPUT=metadata.txt $(NAME).txt
LATEX=$(NAME).latex
PDF=$(NAME).pdf
TEMPLATE=default.latex

all: $(PDF)
	-killall evince
	-explorer $<
	-evince $<

$(PDF): $(LATEX)
	-taskkill -FI 'windowtitle eq $(PDF)*'
	pdflatex -enable-write18 -shell-escape $(LATEX)

$(LATEX): $(INPUT) $(TEMPLATE)
	pandoc \
		--standalone \
		-o $@ \
		$(INPUT)

clean:
	-taskkill -FI 'windowtitle eq $(PDF)*'
	rm $(PDF) $(LATEX)
