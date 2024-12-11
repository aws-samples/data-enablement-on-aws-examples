#!/usr/bin/env python3
import os

import aws_cdk as cdk

from spline.spline_stack import SplineStack


app = cdk.App()
SplineStack(app, "SplineStack")

cdk.Tags.of(app).add("Project", "SplineDemo")

app.synth()
