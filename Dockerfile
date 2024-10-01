FROM ruby:3.3.3-alpine

WORKDIR /app

RUN apk update && apk add --virtual build-dependencies build-base

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY main.rb .
# COPY cookie .

RUN apk add --no-cache curl

CMD ["ruby", "main.rb"]
