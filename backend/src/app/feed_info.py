from fastapi import APIRouter, HTTPException, Request
from .gtfs.models import FeedInfo

router = APIRouter()

@router.get("/feed-info")
def get_feed_info(request: Request) -> FeedInfo:
    feed_info: FeedInfo | None = request.app.state.feed_info
    if feed_info is None:
        raise HTTPException(status_code=404, detail="No feed info available")
    return feed_info