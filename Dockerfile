FROM ruby:3.3.3-alpine

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY main.rb .
COPY cookie .

RUN apk add --no-cache curl

CMD ["ruby", "main.rb"]
