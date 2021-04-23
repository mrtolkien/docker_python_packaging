# Start from the base Docker image you plan to use
FROM tiangolo/uvicorn-gunicorn-fastapi:python3.8 AS env-stage

# Update pip
RUN /usr/local/bin/python -m pip install --upgrade pip

# Starting packages install
# We use a local /build folder to make the process work whether requirements.txt is here or not
WORKDIR /build

COPY /dependencies .

# First, we install version-pinned packages if they were already computed
RUN [ -f requirements.txt ] && pip install -r requirements.txt || echo 0

# Then we install additional logical dependencies in the existing environment
RUN [ -f requirements.in ] && pip install -r requirements.in || echo 0

# We remove our /build folder as it is not needed anymore
RUN rm -rf /build


# INSTALL YOUR DEV DEPENDENCIES HERE
FROM env-stage AS dev-stage
# ...

# PUT ALL YOUR NORMAL APPLICATION PACKAGING LOGIC HERE
# BUILD IT AS USUAL WITH docker build -t app-stage .
FROM env-stage AS app-stage
# ...

# Before the exporting stage, we export requirements.txt to /export
FROM env-stage AS requirements-export-stage
WORKDIR /export
RUN echo "# AUTO GENERATED FILE - DO NOT EDIT BY HAND\n" | \
	tee requirements.txt
RUN pip freeze >> requirements.txt

# Finally, we make our export "image" made only of requirements.txt, ready to be used with `build --output dependencies .`
FROM scratch
COPY --from=requirements-export-stage /export /
