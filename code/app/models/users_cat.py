from pydantic import BaseModel, ConfigDict
from models.user import User


class UsersCat(BaseModel):
    model_config = ConfigDict(frozen=True)

    owner: User
    picture_url: str
