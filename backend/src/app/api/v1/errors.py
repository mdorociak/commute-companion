from fastapi import Request
from fastapi.responses import JSONResponse

from ...active_export import TimetableUnavailable


def timetable_unavailable_error(
    request: Request,
    exc: TimetableUnavailable,
) -> JSONResponse:
    return JSONResponse(
        status_code=503,
        content={"code": "timetable_unavailable"},
    )
