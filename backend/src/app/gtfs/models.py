from pydantic import BaseModel
from datetime import date


class Platform(BaseModel):
    id: str
    code: str | None


class Station(BaseModel):
    id: str
    name: str
    code: str | None
    lat: float
    lon: float
    platforms: list[Platform]


class Route(BaseModel):
    id: str
    short_name: str 


class Trip(BaseModel):
    id: str
    route_id: str  
    service_id: str  
    headsign: str | None

class ServicePattern(BaseModel):
    service_id: str
    weekdays: tuple[bool, bool, bool, bool, bool, bool, bool]
    start_date: date
    end_date: date

class FeedInfo(BaseModel):
    publisher_name: str
    publisher_url: str
    lang: str
    start_date: date | None
    end_date: date | None