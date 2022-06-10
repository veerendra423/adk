FROM algorithm-base:test

ADD image_files /

RUN mkdir /encrypted-output

WORKDIR /app

CMD python3 /app/ml_algorithm.py --output /encrypted-output
