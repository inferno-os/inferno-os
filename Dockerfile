FROM i386/ubuntu:devel

RUN apt-get -y update
RUN apt-get install -y libx11-dev \
	libxext-dev \
	libc6-dev \
	gcc

# if on i386 there's no need for multilib
#RUN apt-get install -y libc6-dev-i386
#RUN apt-get install -y libx11-6:i386, libxext-dev:i386
#RUN apt-get install -y gcc-multilib

ENV INFERNO=/usr/inferno
COPY . $INFERNO
WORKDIR $INFERNO

# setup a custom mkconfig
RUN echo > mkconfig ROOT=$INFERNO
RUN echo >>mkconfig TKSTYLE=std
RUN echo >>mkconfig SYSHOST=Linux
RUN echo >>mkconfig SYSTARG=Linux
RUN echo >>mkconfig OBJTYPE=386

RUN echo >>mkconfig 'OBJDIR=$SYSTARG/$OBJTYPE'
RUN echo >>mkconfig '<$ROOT/mkfiles/mkhost-$SYSHOST'
RUN echo >>mkconfig '<$ROOT/mkfiles/mkfile-$SYSTARG-$OBJTYPE'

# build code
RUN ./makemk.sh
ENV PATH="$INFERNO/Linux/386/bin:${PATH}"
RUN mk nuke
RUN mk install

CMD ["emu", "-c1",  "wm/wm"]

