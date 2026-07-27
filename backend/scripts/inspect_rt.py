import sys
from collections import Counter
from google.transit import gtfs_realtime_pb2

if len(sys.argv) != 2:
    print("Usage: python inspect_rt.py <path-to-.pb>")
    sys.exit(1)

feed = gtfs_realtime_pb2.FeedMessage()
with open(sys.argv[1], "rb") as f:
    feed.ParseFromString(f.read())

print(f"Header: version={feed.header.gtfs_realtime_version}, "
      f"timestamp={feed.header.timestamp}, "
      f"incrementality={feed.header.incrementality}")
print(f"Total entities: {len(feed.entity)}")

types = Counter()
samples = {}
for entity in feed.entity:
    if entity.HasField("trip_update"):
        types["trip_update"] += 1
        samples.setdefault("trip_update", entity)
    if entity.HasField("vehicle"):
        types["vehicle"] += 1
        samples.setdefault("vehicle", entity)
    if entity.HasField("alert"):
        types["alert"] += 1
        samples.setdefault("alert", entity)

print(f"Entity types: {dict(types)}")

for kind, entity in samples.items():
    print()
    print(f"--- Sample {kind} entity ---")
    print(entity)