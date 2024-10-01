FROM ruby:3.3.3-alpine

ARG VERBOSE=false

WORKDIR /app

RUN apk update && apk add --virtual build-dependencies build-base
RUN apk add --no-cache curl

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY main.rb .
COPY cookie .

ENV VERBOSE=${VERBOSE}

CMD ["ruby", "main.rb"]
