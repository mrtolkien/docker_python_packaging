# Docker Python Packaging

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

It is the de-facto accepted paradigm for developing anything python-related with Docker. And it works very well for simpler projects.

## What triggered me to rethink it

One of the main reasons why I love Docker is the **isolation** it provides to my projects.

But if you decide to use a **local** python environment to compute dependencies, you could run into the following issues:
- Having different python versions locally and in your Docker image leading to improper package versions
- Having different operating systems that have different install dependencies for packages (like the very popular `psycopg2` having issues on MacOS)
- Having packages already installed in your Docker image that are not compatible with the versions you will be pinning

So ideally, you need to:
- Run a VM with the **same** operating system as your Docker image
	- Also includes architecture, which I was confronted to when working with my M1 MacBook Air
- Install the **same** python version as your base Docker image in the VM
- If any packages are installed in your [base Docker image](https://hub.docker.com/r/tiangolo/uvicorn-gunicorn-fastapi/), install them in the VM’s enviroment
- Install additional python packages in the VM’s environment and use it as your development environment

But this sounds very much like using Docker itself, doesn’t it?

Which is why I think the right approach should be to do **everything** in Docker. Transitive dependencies should be computed **inside** the base Docker image that will be used.

With this approach, the only local dependency is to have Docker installed. That’s it.

## The solution

The steps needed to keep the full process inside Docker are:
- Start from an existing Docker image
- If a `requirements.txt` file was not already generated, skip to the next step. If it was, install version-pinned packages from it.
- Copy our `requirements.in` logical dependencies file to the image and install the packages with `pip`
- Export our new python environment with `pip freeze` and retrieve the `requirements.txt` to replace our existing one

There are lots of ways to achieve this Docker-only workflow thanks to the new [`BuildKit`](https://docs.docker.com/develop/develop-images/build_enhancements/) tool that was recently added in the mainline Docker releases. It adds the `COPY --from` feature to your `Dockerfile `, which allows you to export only the necessary `requirements.txt` file

You can clone this folder and run `docker build -o build .` to see my very simple implementation.

Here is my `Dockerfile`:
```dockerfile
# Start from the base Docker image you plan to use
FROM tiangolo/uvicorn-gunicorn-fastapi:python3.8 AS env-stage

WORKDIR /build
COPY requirements.in .
RUN pip install -r requirements.in

FROM env-stage AS dev-stage
# INSTALL YOUR DEV DEPENDENCIES HERE
# ADD ANYTHING DEV-RELATED HERE

FROM env-stage AS app-stage
# PUT ALL YOUR NORMAL APP PACKAGING LOGIC HERE
# BUILD IT AS USUAL WITH docker build -t app-stage .

# One middle step to export requirements.txt to /build
# I am separating it from the main image building logic for clarity
FROM env-stage AS requirements-export-stage
WORKDIR /export
RUN echo "# AUTO GENERATED FILE - DO NOT EDIT BY HAND\n" | \
	tee requirements.txt
RUN pip freeze >> requirements.txt

# Finally, we make our export "image" made only of requirements.txt, ready to be used with `build --output . .`
FROM scratch
COPY --from=requirements-export-stage /export /
```

I use the `requirements.in` format from `pip-tools` as they’re the easiest to write humanly, which I prefer over needing tools to format a file the right way.

There are 2 things that can happen in this `Dockerfile`:
- If `requirements.txt` exists -> install the pinned packages with `pip`
- If `requirements.in` exists -> install the packages with `pip` and generate a version-pinned `requirements.txt`

If both files exist, it will first install the version-pinned requirements from `requirements.txt` *then* the logical dependencies of `requirements.in` and update `requirements.txt` after it is done.

To completely recalculate transitive dependencies from your `requirements.in` file, simply delete `requirements.txt` and build again!
