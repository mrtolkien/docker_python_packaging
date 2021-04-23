# Start from the base Docker image you plan to use
FROM tiangolo/uvicorn-gunicorn-fastapi:python3.8 AS env-stage

# Starting packages install
WORKDIR /build

# Update pip
RUN /usr/local/bin/python -m pip install --upgrade pip

# We use a local /build folder to make the process work whether or not requirements.txt is here or not
COPY /build .

# First, we install version-pinned packages if they were already computed
RUN [ -f /build/requirements.txt ] && pip install -r requirements.txt

# Then we install additional logical dependencies in the existing environment
RUN [ -f /build/requirements.in ] && pip install -r requirements.in

# We remove our /build folder as it is not needed anymore
RUN rm -rf /build


# INSTALL YOUR DEV DEPENDENCIES HERE
FROM env-stage AS dev-stage
# ...

# PUT ALL YOUR NORMAL APPLICATION PACKAGING LOGIC HERE
# BUILD IT AS USUAL WITH docker build -t app-stage .
FROM env-stage AS app-stage
# ...

# Before the exporting image, we export requirements.txt to /build
FROM env-stage AS requirements-export-stage
WORKDIR /export
RUN echo "# AUTO GENERATED FILE - DO NOT EDIT BY HAND\n" | \
	tee requirements.txt
RUN pip freeze >> requirements.txt

# Finally, we make our export "image" made only of requirements.txt, ready to be used with `build --output build .`
FROM scratch
COPY --from=requirements-export-stage /export /
