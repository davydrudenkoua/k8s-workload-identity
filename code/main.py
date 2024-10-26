from io import BytesIO
from models.user import User
from models.users_cat import UsersCat
from services.blob_storage_service import CatPicsStorageService
from fastapi import FastAPI, HTTPException, UploadFile

cat_pics = CatPicsStorageService()
app = FastAPI()


@app.get("/cat/{user}")
async def get_users_cat_pic(user: str):
    blob_url = cat_pics.get_readonly_url(blob="cat", path=user)

    if not blob_url:
        raise HTTPException(status_code=404, detail="Cat not found")

    return UsersCat(owner=User(name=user), picture_url=blob_url)


@app.post("/cat/{user}")
async def upload_users_cat_pic(user: str, file: UploadFile):
    content = await file.read()
    result = cat_pics.upload_pic(
        path=user, blob="cat", file=BytesIO(content), content_type=file.content_type
    )

    if not result:
        raise HTTPException(status_code=500, detail="Something went wrong")
    return {}
