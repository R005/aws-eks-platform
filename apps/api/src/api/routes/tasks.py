"""CRUD endpoints for tasks."""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from api.db import get_session
from api.models import Task
from api.schemas import TaskCreate, TaskRead, TaskUpdate

router = APIRouter(prefix="/tasks", tags=["tasks"])
SessionDep = Annotated[Session, Depends(get_session)]


def _get_or_404(session: Session, task_id: int) -> Task:
    task = session.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="task not found")
    return task


@router.get("", response_model=list[TaskRead])
def list_tasks(
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[Task]:
    return list(session.scalars(select(Task).order_by(Task.id).limit(limit).offset(offset)))


@router.post("", response_model=TaskRead, status_code=status.HTTP_201_CREATED)
def create_task(body: TaskCreate, session: SessionDep) -> Task:
    task = Task(title=body.title)
    session.add(task)
    session.commit()
    session.refresh(task)  # load server-generated id and created_at
    return task


@router.get("/{task_id}", response_model=TaskRead)
def get_task(task_id: int, session: SessionDep) -> Task:
    return _get_or_404(session, task_id)


@router.patch("/{task_id}", response_model=TaskRead)
def update_task(task_id: int, body: TaskUpdate, session: SessionDep) -> Task:
    task = _get_or_404(session, task_id)
    # exclude_none: an explicit `"title": null` is ignored rather than violating NOT NULL
    for field, value in body.model_dump(exclude_unset=True, exclude_none=True).items():
        setattr(task, field, value)
    session.commit()
    session.refresh(task)
    return task


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: int, session: SessionDep) -> Response:
    session.delete(_get_or_404(session, task_id))
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
