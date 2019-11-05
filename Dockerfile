FROM flybase/harvdev-docker:latest

WORKDIR /src

RUN mkdir /output

ENV PERL5LIB=/src/lib/perl5

ADD . .

CMD ["perl", "/src/production/Peeves", "/proforma/input/explore_chado.cfg", "/proforma/input/test_files.cfg"]
