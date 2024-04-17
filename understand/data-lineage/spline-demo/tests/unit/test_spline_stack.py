import aws_cdk as core
import aws_cdk.assertions as assertions

from spline.spline_stack import SplineStack


def test_sqs_queue_created():
    app = core.App()
    stack = SplineStack(app, "spline")
    template = assertions.Template.from_stack(stack)

