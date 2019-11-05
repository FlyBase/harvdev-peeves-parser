FROM flybase/harvdev-docker:latest

WORKDIR /src

RUN mkdir /output

ENV PERL5LIB=/src/lib/perl5

ADD . .

ADD /data/harvcur/svn/ontologies/trunk /ontologies

CMD ["perl", "/src/production/Peeves", "/src/explore_chado.cfg", "/src/test_files.cfg"]
