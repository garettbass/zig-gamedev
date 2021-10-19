#include "cbullet.h"
#include <assert.h>
#include "btBulletCollisionCommon.h"
#include "btBulletDynamicsCommon.h"

struct CbtDebugDraw : public btIDebugDraw {
    CbtDebugDrawCallbacks callbacks = {};
    int debug_mode = 0;

    virtual void drawLine(const btVector3& from, const btVector3& to, const btVector3& color) override {
        if (callbacks.drawLine) {
            const CbtVector3 p0 = { from.x(), from.y(), from.z() };
            const CbtVector3 p1 = { to.x(), to.y(), to.z() };
            const CbtVector3 c = { color.x(), color.y(), color.z() };
            callbacks.drawLine(p0, p1, c, callbacks.user_data);
        }
    }

    virtual void drawContactPoint(
        const btVector3& point,
        const btVector3& normal,
        btScalar distance,
        int life_time,
        const btVector3& color
    ) override {
        if (callbacks.drawContactPoint) {
            const CbtVector3 p = { point.x(), point.y(), point.z() };
            const CbtVector3 n = { normal.x(), normal.y(), normal.z() };
            const CbtVector3 c = { color.x(), color.y(), color.z() };
            callbacks.drawContactPoint(p, n, distance, life_time, c, callbacks.user_data);
        }
    }

    virtual void reportErrorWarning(const char* warning_string) override {
        if (callbacks.reportErrorWarning && warning_string) {
            callbacks.reportErrorWarning(warning_string, callbacks.user_data);
        }
    }

    virtual void draw3dText(const btVector3&, const char*) override {
    }

    virtual void setDebugMode(int in_debug_mode) override {
        debug_mode = in_debug_mode;
    }

    virtual int getDebugMode() const override {
        return debug_mode;
    }
};

CbtWorldHandle cbtWorldCreate(void) {
    btDefaultCollisionConfiguration* collision_config = new btDefaultCollisionConfiguration();
    btCollisionDispatcher* dispatcher = new btCollisionDispatcher(collision_config);
    btBroadphaseInterface* broadphase = new btDbvtBroadphase();
    btSequentialImpulseConstraintSolver* solver = new btSequentialImpulseConstraintSolver();
    btDiscreteDynamicsWorld* world = new btDiscreteDynamicsWorld(dispatcher, broadphase, solver, collision_config);
    return (CbtWorldHandle)world;
}

void cbtWorldDestroy(CbtWorldHandle handle) {
    btDiscreteDynamicsWorld* world = (btDiscreteDynamicsWorld*)handle;
    assert(world);

    if (world->getDebugDrawer()) {
        delete world->getDebugDrawer();
    }

    btCollisionDispatcher* dispatcher = (btCollisionDispatcher*)world->getDispatcher();
    delete dispatcher->getCollisionConfiguration();
    delete dispatcher;

    delete world->getBroadphase();
    delete world->getConstraintSolver();
    delete world;
}

void cbtWorldSetGravity(CbtWorldHandle handle, float gx, float gy, float gz) {
    btDiscreteDynamicsWorld* world = (btDiscreteDynamicsWorld*)handle;
    assert(world);
    world->setGravity(btVector3(gx, gy, gz));
}

int cbtWorldStepSimulation(CbtWorldHandle handle, float time_step, int max_sub_steps, float fixed_time_step) {
    btDiscreteDynamicsWorld* world = (btDiscreteDynamicsWorld*)handle;
    assert(world);
    return world->stepSimulation(time_step, max_sub_steps, fixed_time_step);
}

void cbtWorldDebugSetCallbacks(CbtWorldHandle handle, const CbtDebugDrawCallbacks* callbacks) {
    btDiscreteDynamicsWorld* world = (btDiscreteDynamicsWorld*)handle;
    assert(world && callbacks);

    CbtDebugDraw* debug = (CbtDebugDraw*)world->getDebugDrawer();
    if (debug == nullptr) {
        debug = new CbtDebugDraw();
        debug->setDebugMode(btIDebugDraw::DBG_DrawWireframe | btIDebugDraw::DBG_DrawFrames);
        world->setDebugDrawer(debug);
    }

    debug->callbacks = *callbacks;
}

void cbtWorldDebugDraw(CbtWorldHandle handle) {
    btDiscreteDynamicsWorld* world = (btDiscreteDynamicsWorld*)handle;
    assert(world);
    world->debugDrawWorld();
}

void cbtWorldDebugDrawLine(CbtWorldHandle handle, const CbtVector3 p0, const CbtVector3 p1, const CbtVector3 color) {
    assert(p0 && p1 && color);
    btDiscreteDynamicsWorld* world = (btDiscreteDynamicsWorld*)handle;
    assert(world && world->getDebugDrawer());

    world->getDebugDrawer()->drawLine(
        btVector3(p0[0], p0[1], p0[2]),
        btVector3(p1[0], p1[1], p1[2]),
        btVector3(color[0], color[1], color[2])
    );
}

void cbtWorldDebugDrawSphere(CbtWorldHandle handle, const CbtVector3 position, float radius, const CbtVector3 color) {
    assert(position && radius > 0.0 && color);
    btDiscreteDynamicsWorld* world = (btDiscreteDynamicsWorld*)handle;
    assert(world && world->getDebugDrawer());

    world->getDebugDrawer()->drawSphere(
        btVector3(position[0], position[1], position[2]),
        radius,
        btVector3(color[0], color[1], color[2])
    );
}

int cbtShapeGetType(CbtShapeHandle handle) {
    btCollisionShape* shape = (btCollisionShape*)handle;
    assert(shape);
    return shape->getShapeType();
}

CbtShapeHandle cbtShapeCreateBox(float half_x, float half_y, float half_z) {
    assert(half_x > 0.0 && half_y > 0.0 && half_z > 0.0);
    btBoxShape* box = new btBoxShape(btVector3(half_x, half_y, half_z));
    return (CbtShapeHandle)box;
}

CbtShapeHandle cbtShapeCreateSphere(float radius) {
    assert(radius > 0.0f);
    btSphereShape* sphere = new btSphereShape(radius);
    return (CbtShapeHandle)sphere;
}

CbtShapeHandle cbtShapeCreatePlane(float nx, float ny, float nz, float d) {
    btStaticPlaneShape* cbtane = new btStaticPlaneShape(btVector3(nx, ny, nz), d);
    return (CbtShapeHandle)cbtane;
}

CbtShapeHandle cbtShapeCreateCapsule(float radius, float height, int up_axis) {
    assert(up_axis >= 0 && up_axis <= 2);
    assert(radius > 0.0 && height > 0);

    btCapsuleShape* capsule = nullptr;
    if (up_axis == 0) {
        capsule = new btCapsuleShapeX(radius, height);
    } else if (up_axis == 2) {
        capsule = new btCapsuleShapeZ(radius, height);
    } else {
        capsule = new btCapsuleShape(radius, height);
    }
    return (CbtShapeHandle)capsule;
}

void cbtShapeDestroy(CbtShapeHandle handle) {
    btCollisionShape* shape = (btCollisionShape*)handle;
    assert(shape);
    delete shape;
}

CbtBodyHandle cbtBodyCreate(
    CbtWorldHandle world_handle,
    float mass,
    const CbtVector3 transform[4],
    CbtShapeHandle shape_handle
) {
    btDiscreteDynamicsWorld* world = (btDiscreteDynamicsWorld*)world_handle;
    btCollisionShape* shape = (btCollisionShape*)shape_handle;
    assert(world && shape && transform && mass >= 0.0f);

    const bool is_dynamic = (mass != 0.0f);

    btVector3 local_inertia(0.0f, 0.0f, 0.0f);
    if (is_dynamic)
        shape->calculateLocalInertia(mass, local_inertia);

    btDefaultMotionState* motion_state = new btDefaultMotionState(
        btTransform(
            btMatrix3x3(
                btVector3(transform[0][0], transform[0][1], transform[0][2]),
                btVector3(transform[1][0], transform[1][1], transform[1][2]),
                btVector3(transform[2][0], transform[2][1], transform[2][2])
            ),
            btVector3(transform[3][0], transform[3][1], transform[3][2])
        )
    );

    btRigidBody::btRigidBodyConstructionInfo info(mass, motion_state, shape, local_inertia);
    btRigidBody* body = new btRigidBody(info);
    world->addRigidBody(body);

    return (CbtBodyHandle)body;
}

void cbtBodyDestroy(CbtWorldHandle world_handle, CbtBodyHandle body_handle) {
    btDiscreteDynamicsWorld* world = (btDiscreteDynamicsWorld*)world_handle;
    btRigidBody* body = (btRigidBody*)body_handle;
    assert(world && body);

    if (body->getMotionState()) {
        delete body->getMotionState();
    }
    world->removeRigidBody(body);
    delete body;
}

void cbtBodyGetGraphicsTransform(CbtBodyHandle handle, CbtVector3 transform[4]) {
    btRigidBody* body = (btRigidBody*)handle;
    assert(body && body->getMotionState() && transform);

    btTransform trans;
    body->getMotionState()->getWorldTransform(trans);

    const btMatrix3x3& basis = trans.getBasis();
    const btVector3& origin = trans.getOrigin();

    transform[0][0] = basis.getRow(0).x();
    transform[0][1] = basis.getRow(0).y();
    transform[0][2] = basis.getRow(0).z();
    transform[1][0] = basis.getRow(1).x();
    transform[1][1] = basis.getRow(1).y();
    transform[1][2] = basis.getRow(1).z();
    transform[2][0] = basis.getRow(2).x();
    transform[2][1] = basis.getRow(2).y();
    transform[2][2] = basis.getRow(2).z();

    transform[3][0] = origin.x();
    transform[3][1] = origin.y();
    transform[3][2] = origin.z();
}