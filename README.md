# Rethinking Docker Python Packaging

## TL;DR
This repository is about computing transitive dependencies from logical dependencies inside Docker instead of relying on a local virtual environment.

You can try it with:
```shell
git clone https://github.com/mrtolkien/docker_python_packaging.git
cd docker_python_packaging
docker build --output dependencies .
```

This will export transitive dependencies to `/dependencies/requirements.txt`

## Reviewing the best practices

The agreed upon best practice for using Python and Docker is to:
- Use a **local** python virtual environment
- Install packages **locally** through `pip`, `pipenv`, `poetry`, or `pip-tools`
- Export the [transitive dependencies](https://en.wikipedia.org/wiki/Transitive_dependency) to a version-pinned `requirements.txt`
- Use that `requirements.txt` to install packages with `pip` when building the Docker image to ensure reproducibility

This approach is recommended by:
- [The Docker documentation itself](https://docs.docker.com/language/python/build-images/)
- [VS Code tutorials](https://code.visualstudio.com/docs/containers/quickstart-python)
- [RealPython tutorials](https://github.com/realpython/orchestrating-docker)

It is the de-facto accepted paradigm for developing anything python-related with Docker. It works very well for simpler projects, and does ensure reproducibility once the requirements have been computed.

## What triggered me to rethink it

One of the main reasons why I love Docker is the **isolation** it provides to my projects.

But if you decide to use a **local** python environment to compute transtive dependencies, you could run into the following issues:
- Having different python versions locally and in your Docker image leading to improper package versions
- Having different operating systems that have different install/build dependencies for binary packages
- Having packages already installed in your base Docker image that are not compatible with the versions you will be pinning

So ideally, you need to:
- Run a VM with the **same** operating system as your base Docker image
	- This also includes architecture, which I was confronted to when working with my M1 MacBook Air
- Install the **same** python version as your base Docker image in the VM
- If any packages are installed in your [base Docker image](https://hub.docker.com/r/tiangolo/uvicorn-gunicorn-fastapi/), install them in the VM’s enviroment
- Install additional python packages in the VM’s environment and use it as your development environment

But this sounds very much like something Docker would be great at, doesn’t it?

Which is why I think the right approach should be to do **everything** in Docker. Transitive dependencies should be computed **inside** the base Docker image that will be used, and require only Docker to be installed to be computed.

## My solution

My approach to keep the full process inside Docker is to use a logical dependency list of packages (`requirements.in`) and use it to compute transitive dependencies (`requirements.txt`) during the build process. That way I only maintain `requirements.in` and generate a `requirements.txt` from it when needed, and it will then be used in the final application build process. 

My process steps are:
- Start from any Docker image, ideally pinning a mostly static image
- If they exist, install pinned dependencies from `requirements.txt`
- Else, install logical dependencies from `requirements.in` with `pip`
	- In this situation, export our new python environment with `pip freeze` and retrieve the generated `requirements.txt` locally to be used in future builds

With this setup, deleting `requirements.txt` will trigger a full recalculation of transitive dependencies.

This process is made easy thanks to the [`BuildKit`](https://docs.docker.com/develop/develop-images/build_enhancements/) tool that was recently added in the mainline Docker releases. It adds the `COPY --from` feature to our `Dockerfile`, which allows us to export only the necessary `requirements.txt` file from our build. We also use `--mount=type=cache` to speed up the process and cache our `pypi` packages.

You can clone this repository and run `docker build --output dependencies .` to see my simple implementation. It should generate a `/dependencies/requirements.txt` file.

Here is the `Dockerfile`, which adds `sqlalchemy` and `psycopg2` to the [official `FastAPI` Docker image](https://hub.docker.com/r/tiangolo/uvicorn-gunicorn-fastapi/) :
```dockerfile
# Start from the base Docker image you plan to use
FROM tiangolo/uvicorn-gunicorn-fastapi:python3.8 AS env-stage

# Update pip
RUN /usr/local/bin/python -m pip install --upgrade pip

# Starting packages install
# We use a local /build folder to make the process work whether requirements.txt is here or not
WORKDIR /build

COPY /dependencies .

# We install from requirements.txt if it exists, and if not we install from requirements.in
# We use --mount=type=cache to reduce re-downloads from pipy
RUN --mount=type=cache,target=/root/.cache/pip \
	[ -f requirements.txt ] && \
	pip install -r requirements.txt || \
	pip install -r requirements.in

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
# Making the file read-only to make sure it is not overwritten by mistake
RUN chmod 0444 requirements.txt

# Finally, we make our export "image" made only of requirements.txt, ready to be used with `build --output dependencies .`
FROM scratch
COPY --from=requirements-export-stage /export /
```

## Closing words

Of course, this is a very rough implementation and a lot of things could be done to improve it, make it more reliable, and more importantly standardize this files locations.

But what it shows is how to work **fully** in Docker for a python project, and never have to care about any local environment while still keeping the same level of reproducibility.

Working that way has benefits over the standard paradigm of maintaining a local enviroment. It allows you to stop caring about:
- OS
- Architecture
- Python version
- Existing packages in your Docker images

This makes it much easier to create the proper development environment, and therefore to work accross multiple machines and users. It could also save development time by ensuring there are no package compatibility issues from the very start, instead of discovering it after having worked in a local environment.

But I am still a relatively new Docker user and might be wrong on what I am trying to do, so do not hesitate to comment why you’re in favor or against this approach in the [github discussions forum](https://github.com/mrtolkien/docker_python_packaging/discussions)!
